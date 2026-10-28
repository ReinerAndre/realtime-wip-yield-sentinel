---

### 3. O Guia do Usuário (`user_guide.md`)

# Guia do Usuário: Relatório de Gestão de Perdas em Tempo Real

## 📖 Visão Geral
Este documento orienta supervisores de turno, encarregados de produção e analistas de PCP no uso do relatório de monitoramento contínuo de perdas entre etapas no ERP Iniflex.

O objetivo do relatório é fornecer **gestão à vista antecipada**, permitindo intervir em desvios operacionais enquanto a Ordem de Produção (OP) ainda está em processo (`P`), sem depender do fechamento da ordem.

---

## 🚦 Critérios do Farol Operacional

O sistema calcula o saldo esperado da etapa anterior, compara com a produção realizada e aplica a tolerância calculada para a OP:

| Status Farol | Condição Técnica | Interpretação no Chão de Fábrica | Ação do Supervisor |
| :--- | :--- | :--- | :--- |
| **`OK`** | Realizado >= Liberado anterior | Processo estável; material totalmente justificado. | Nenhuma ação necessária. |
| **`ALERTA LEVE`** | Perda apurada < Margem da OP | Refugo dentro do padrão de setup/processo esperado. | Acompanhamento de rotina. |
| **`ATENÇÃO`** | Perda >= Margem da OP, mas <= 2.000m | Margem estourada em lote pequeno ou desvio inicial. | Verificar regulagem de máquina e setup sem interromper o fluxo. |
| **`CRÍTICO`** | Perda >= Margem da OP **E** Desvio > 2.000m | **Anomalia Operacional Severa:** Desvio volumétrico significativo em andamento. | **Intervenção Imediata na Máquina:** Auditar processo e apontamentos antes de liberar a etapa seguinte. |

---

## ⚙️ Filtros Disponíveis no JasperReports

- **Empresa (`$P{global.empresa.codigo}`):** Código da unidade fabril ativo na sessão.
- **Etapa Atual / Etapa Anterior (`$X{..., filtroPcpetapa}`):** Permite isolar gargalos específicos (ex.: Perdas entre Etapa 20 - Impressão e Etapa 35 - Rebobinamento).
- **Recurso / Máquina (`$X{..., filtroPcprecurso}`):** Filtra os apontamentos realizados em um equipamento específico.
- **Ordem de Produção (`$X{..., filtroPcpop}`):** Consulta direcionada para investigação de uma OP em lote.
- **Filtro de Status (`$X{..., filtrostatus}`):** Permite listar unicamente ordens em estado `CRÍTICO` ou `ATENÇÃO` para atuação prioritária.

---

## 📋 Protocolo de Investigação para Alertas `CRÍTICO`

Ao identificar uma OP em status crítico no relatório:
1. **Conferência Física:** Dirija-se ao equipamento indicado na coluna `nome_recurso` e verifique a contagem de bobinas/volumes processados.
2. **Apontamentos Parciais:** Confirme se o operador realizou o apontamento parcial de produção sem registrar o refugo correspondente na mesma proporção.
3. **Validação da Etapa Predecessora:** Verifique se o saldo liberado pela etapa anterior foi superestimado na pesagem ou metragem.
4. **Registro de Motivo:** Certifique-se de que toda perda física constatada seja classificada com o respectivo código de motivo no Iniflex antes de encerrar o turno.
