-- =====================================================================================
-- PIPELINE: Monitoramento de Rendimento e Detecção de Perda Oculta em Tempo Real (WIP)
-- MOTOR: Oracle SQL / Dialeto JasperReports (Filtros $P{} e $X{})
-- OBJETIVO: Permitir ação imediata do supervisor no chão de fábrica antes do encerramento da OP
-- =====================================================================================

SELECT * 
FROM (
    WITH EngenhariaToleranciaOP AS (
        -- 1. Engenharia Reversa do Empenho:
        -- Calcula dinamicamente o % de perda técnica previsto na Ordem de Produção (choro)
        -- comparando a matéria-prima alocada contra a necessidade estrita da ficha técnica.
        SELECT 
            comp.empresa_id,
            comp.ordem_producao_id,
            MAX(comp.volume_empenhado_total) AS volume_empenhado_planejado,
            MAX(op.quantidade_planejada * ficha.fator_conversao) AS volume_teorico_liquido,
            ROUND(
                (MAX(comp.volume_empenhado_total) / NULLIF(MAX(op.quantidade_planejada * ficha.fator_conversao), 0)) - 1, 
                4
            ) AS perc_tolerancia_dinamica
        FROM erp_producao.ordem_componente comp
        INNER JOIN erp_producao.ordem_producao op 
            ON op.empresa_id = comp.empresa_id 
           AND op.ordem_producao_id = comp.ordem_producao_id
        INNER JOIN erp_engenharia.ficha_tecnica_item ficha 
            ON ficha.empresa_id = comp.empresa_id 
           AND ficha.produto_id = op.produto_id 
           AND ficha.versao_id = op.versao_id 
           AND ficha.sequencial_componente = comp.sequencial_componente
        INNER JOIN erp_producao.ordem_grupo_componente grupo 
            ON grupo.empresa_id = comp.empresa_id 
           AND grupo.ordem_producao_id = comp.ordem_producao_id 
           AND grupo.grupo_id = comp.grupo_id
        WHERE op.empresa_id = $P{global_empresa_id}
          AND grupo.descricao_grupo LIKE '%MATERIA PRIMA%'
          AND op.status_ordem IN ('EM_PROCESSO')
        GROUP BY comp.empresa_id, comp.ordem_producao_id
    ),

    ApontamentosPorEtapa AS (
        -- 2. Consolidação de Apontamentos de Produção e Refugo:
        -- Captura o saldo já processado (bom + refugo) e o recurso (máquina) do apontamento ativo.
        SELECT 
            roteiro.empresa_id,
            roteiro.ordem_producao_id,
            roteiro.sequencia_etapa,
            roteiro.etapa_id,
            NVL(SUM(apont.quantidade_produzida), 0) AS qtd_produzida_boa,
            NVL(SUM(refugo.quantidade_refugo), 0)    AS qtd_refugo_registrado,
            MAX(apont.recurso_id)                    AS recurso_id,
            MAX(op.produto_id)                       AS produto_id, 
            MAX(op.versao_id)                        AS versao_id
        FROM erp_producao.ordem_roteiro_etapa roteiro
        INNER JOIN erp_engenharia.etapas_processo ep 
            ON ep.empresa_id = roteiro.empresa_id 
           AND ep.etapa_id = roteiro.etapa_id 
           AND ep.flag_retrabalho = 'N'
        INNER JOIN erp_producao.ordem_producao op 
            ON op.empresa_id = roteiro.empresa_id 
           AND op.ordem_producao_id = roteiro.ordem_producao_id
        LEFT JOIN erp_chao_fabrica.apontamento_producao apont 
            ON apont.empresa_id = roteiro.empresa_id 
           AND apont.ordem_producao_id = roteiro.ordem_producao_id 
           AND apont.etapa_id = roteiro.etapa_id
        LEFT JOIN erp_chao_fabrica.apontamento_refugo refugo 
            ON refugo.empresa_id = roteiro.empresa_id 
           AND refugo.ordem_producao_id = roteiro.ordem_producao_id 
           AND refugo.etapa_id = roteiro.etapa_id 
           AND refugo.motivo_perda_id NOT IN (1, 2)
        WHERE roteiro.empresa_id = $P{global_empresa_id}
          AND op.status_ordem IN ('EM_PROCESSO')
        GROUP BY roteiro.empresa_id, roteiro.ordem_producao_id, roteiro.sequencia_etapa, roteiro.etapa_id
    ),

    FatorConversao AS (
        -- 3. Resgate do Fator Técnico de Transformação:
        -- Garante a coerência do balanço de massa quando há mudança de unidade entre etapas.
        SELECT 
            ape.empresa_id,
            ape.ordem_producao_id,
            ape.sequencia_etapa,
            MAX(ft.fator_conversao) AS fator_conversao
        FROM ApontamentosPorEtapa ape
        LEFT JOIN erp_engenharia.ficha_tecnica_item ft 
            ON ft.empresa_id = ape.empresa_id 
           AND ft.produto_id = ape.produto_id 
           AND ft.versao_id = ape.versao_id 
           AND ft.sequencial_aplicacao = 1
        LEFT JOIN erp_engenharia.grupo_materia_prima gmp 
            ON gmp.empresa_id = ft.empresa_id 
           AND gmp.grupo_id = ft.grupo_id 
           AND gmp.descricao LIKE '%MATERIA PRIMA%'
        GROUP BY ape.empresa_id, ape.ordem_producao_id, ape.sequencia_etapa
    ),

    AnaliseComLag AS (
        -- 4. Função Analítica de Janela (Window Function):
        -- O LAG() busca o volume da etapa imediatamente anterior no fluxo sem cursores ou loops.
        SELECT 
            ape.empresa_id,
            ape.ordem_producao_id,
            ape.sequencia_etapa,
            ape.etapa_id,
            ape.recurso_id,
            ape.qtd_produzida_boa,
            ape.qtd_refugo_registrado,
            LAG(ape.qtd_produzida_boa) OVER (
                PARTITION BY ape.empresa_id, ape.ordem_producao_id 
                ORDER BY ape.sequencia_etapa
            ) AS volume_liberado_etapa_ant,
            LAG(ape.etapa_id) OVER (
                PARTITION BY ape.empresa_id, ape.ordem_producao_id 
                ORDER BY ape.sequencia_etapa
            ) AS etapa_anterior_id,
            NVL(fc.fator_conversao, 1) AS fator_conversao,
            NVL(eng.perc_tolerancia_dinamica, 0) AS perc_tolerancia_op
        FROM ApontamentosPorEtapa ape
        LEFT JOIN FatorConversao fc 
            ON fc.empresa_id = ape.empresa_id 
           AND fc.ordem_producao_id = ape.ordem_producao_id 
           AND fc.sequencia_etapa = ape.sequencia_etapa
        LEFT JOIN EngenhariaToleranciaOP eng 
            ON eng.empresa_id = ape.empresa_id 
           AND eng.ordem_producao_id = ape.ordem_producao_id
    ),

    CalculoDesvio AS (
        -- 5. Tratamento de Transformação e Balanço Realizado:
        SELECT 
            empresa_id,
            ordem_producao_id,
            sequencia_etapa,
            etapa_anterior_id,
            etapa_id AS etapa_atual_id,
            recurso_id,
            volume_liberado_etapa_ant,
            qtd_produzida_boa,
            qtd_refugo_registrado,
            perc_tolerancia_op,
            -- Ajuste do divisor para etapas que convertem a unidade de medida
            CASE 
                WHEN etapa_id = 60 AND fator_conversao > 0 
                    THEN (volume_liberado_etapa_ant / fator_conversao)
                ELSE volume_liberado_etapa_ant 
            END AS volume_esperado_ajustado,
            (qtd_produzida_boa + qtd_refugo_registrado) AS volume_realizado_atual
        FROM AnaliseComLag
    )

    -- 6. Camada de Apresentação e Classificação Operacional
    SELECT 
        cd.empresa_id,
        cd.ordem_producao_id,
        cd.etapa_anterior_id,
        cd.etapa_atual_id,
        cd.recurso_id AS codigo_recurso,
        rec.nome_recurso,
        ROUND(cd.volume_esperado_ajustado, 2) AS qtd_liberada_etapa_ant,
        cd.volume_realizado_atual             AS qtd_realizada_etapa_atual,
        ROUND(cd.perc_tolerancia_op * 100, 2) AS percentual_perda_prevista,
        
        -- Perda em aberto (ainda não justificada nem como produto bom nem como refugo)
        CASE 
            WHEN cd.volume_realizado_atual < cd.volume_esperado_ajustado 
                THEN ROUND(cd.volume_esperado_ajustado - cd.volume_realizado_atual, 5)
            ELSE 0 
        END AS perda_oculta_pendente,
        
        -- Farol Inteligente: Tolerância Dinâmica da OP combinada com Trava de Impacto (> 2.000m)
        CASE 
            WHEN (cd.volume_esperado_ajustado - cd.volume_realizado_atual) >= (cd.volume_esperado_ajustado * cd.perc_tolerancia_op) 
             AND (cd.volume_esperado_ajustado - cd.volume_realizado_atual) > 2000 
                 THEN 'CRÍTICO (Estourou cota e > 2.000m)'
                 
            WHEN (cd.volume_esperado_ajustado - cd.volume_realizado_atual) >= (cd.volume_esperado_ajustado * cd.perc_tolerancia_op) 
                 THEN 'ATENÇÃO (Margem consumida, vol. baixo)'
                 
            WHEN cd.volume_realizado_atual < cd.volume_esperado_ajustado 
                 THEN 'ALERTA LEVE (Dentro da tolerância)'
                 
            ELSE 'OK'
        END AS status_farol
        
    FROM CalculoDesvio cd
    LEFT JOIN erp_engenharia.cadastro_recursos rec 
           ON rec.empresa_id = cd.empresa_id 
          AND rec.codigo_recurso = cd.recurso_id
    WHERE cd.etapa_anterior_id IS NOT NULL 
      AND cd.volume_realizado_atual > 0 
      AND cd.empresa_id = $P{global_empresa_id}
      AND $X{EQUAL, cd.etapa_atual_id, filtro_etapa_atual}
      AND $X{EQUAL, cd.etapa_anterior_id, filtro_etapa_anterior}
      AND $X{EQUAL, cd.recurso_id, filtro_recurso}
      AND $X{EQUAL, cd.ordem_producao_id, filtro_ordem_producao}
    ORDER BY 
        cd.empresa_id, cd.ordem_producao_id, cd.etapa_atual_id
) consolidado
WHERE $X{EQUAL, status_farol, filtro_status_farol}
