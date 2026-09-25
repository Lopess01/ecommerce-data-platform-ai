-- gold.vendas_temporais — Diretoria Comercial: quando e por qual canal vendemos.
--
-- PORQUÊ das regras:
-- - Uma linha por data × hora × canal_venda: é o menor grão que responde "quanto
--   vendemos por dia, hora, dia da semana e canal" sem perder detalhe; somar as
--   linhas dá qualquer visão mais agregada (por dia, por canal, total).
-- - Todas as vendas entram, inclusive de produto não cadastrado: dinheiro que
--   entrou é receita. A tabela lê direto de silver.vendas, sem join que filtre.
-- - dia_semana_num (1 = domingo ... 7 = sábado) existe para ordenar os dias da
--   semana corretamente; ordenar pelo nome em texto deixa "Domingo" antes de
--   "Quarta" e embaralha a semana.
-- - clientes_unicos é COUNT DISTINCT dentro da linha: somar entre linhas conta o
--   mesmo cliente várias vezes. Para clientes únicos no período o certo é
--   gold.clientes_segmentacao; o aviso vai no comentário para o Genie não errar.
-- - receita com CAST explícito para DECIMAL(10,2): SUM aumenta a precisão do
--   decimal e o tipo declarado precisa bater com o da consulta.

CREATE OR REFRESH MATERIALIZED VIEW gold.vendas_temporais (
  data DATE COMMENT 'Data da venda (sem hora), pelo calendário UTC.',
  dia_semana STRING COMMENT 'Dia da semana da venda em português: Domingo, Segunda, Terça, Quarta, Quinta, Sexta ou Sábado. Para ordenar os dias, use dia_semana_num.',
  dia_semana_num INT COMMENT 'Número do dia da semana para ordenação: 1 = Domingo, 2 = Segunda ... 7 = Sábado.',
  hora INT COMMENT 'Hora do dia da venda em UTC, de 0 a 23 (horário de Brasília = UTC - 3 horas).',
  canal_venda STRING COMMENT 'Canal da venda: ecommerce (loja online) ou loja_fisica. Valores sempre em minúsculas.',
  total_vendas BIGINT COMMENT 'Quantidade de vendas (pedidos) na data, hora e canal. Pode ser somada entre linhas.',
  itens_vendidos BIGINT COMMENT 'Quantidade de unidades vendidas (soma de quantidade) na data, hora e canal. Pode ser somada entre linhas.',
  receita DECIMAL(10,2) COMMENT 'Receita em R$ na data, hora e canal: soma de quantidade x preço unitário de todas as vendas, inclusive de produto não cadastrado. Pode ser somada entre linhas.',
  clientes_unicos BIGINT COMMENT 'Clientes distintos que compraram na data, hora e canal. ATENÇÃO: não some esta coluna entre linhas (o mesmo cliente aparece em várias linhas); para clientes únicos no período use gold.clientes_segmentacao.'
)
COMMENT 'Use para perguntas de QUANDO e POR QUAL CANAL vendemos: vendas, itens e receita por dia, hora, dia da semana e canal (ecommerce ou loja_fisica). Uma linha por data x hora x canal_venda. Valores em R$ referentes ao período de 13/12/2025 a 11/01/2026, incluindo todas as vendas. Para produtos use gold.vendas_produtos; para cruzar com cliente, região ou categoria use gold.vendas_detalhadas.'
AS
SELECT
  data,
  dia_semana,
  dia_semana_num,
  hora,
  canal_venda,
  COUNT(*) AS total_vendas,
  SUM(quantidade) AS itens_vendidos,
  CAST(SUM(receita) AS DECIMAL(10,2)) AS receita,
  COUNT(DISTINCT id_cliente) AS clientes_unicos
FROM silver.vendas
GROUP BY data, dia_semana, dia_semana_num, hora, canal_venda
