-- gold.clientes_segmentacao — Diretoria de Customer Success.
--
-- PORQUÊ das regras:
-- - Uma linha por cliente, INCLUSIVE quem nunca comprou: o LEFT JOIN parte de
--   silver.clientes e a receita desses clientes fica 0. É justamente esse
--   cliente que o time de CS precisa ativar, então ele não pode sumir da tabela.
-- - Todas as vendas entram, inclusive de produto não cadastrado: dinheiro que
--   entrou é receita (a marcação de qualidade fica na silver, não filtra aqui).
-- - Segmentação definida com a diretora a partir da distribuição real da receita
--   por cliente no período (13/12/2025 a 11/01/2026):
--     VIP      receita >= R$ 22.000
--     TOP_TIER receita >= R$ 17.000 e < R$ 22.000
--     REGULAR  receita <  R$ 17.000
--   Os limites antigos (VIP a partir de R$ 10.000, intermediário a partir de
--   R$ 5.000) não serviam: o menor cliente comprou R$ 9.665,29 e a mediana é
--   ~R$ 19.100, então 49 dos 50 clientes viravam VIP e o segmento deixava de
--   separar alguém. Os novos limites dão 10 VIP, 25 TOP_TIER e 15 REGULAR.
-- - ranking_receita usa ROW_NUMBER com desempate por id_cliente, para o ranking
--   ser estável entre execuções.
-- - Colunas e tabela comentadas porque a tabela é usada por dashboard e pelo
--   Genie, que escreve SQL lendo esses comentários.

CREATE OR REFRESH MATERIALIZED VIEW gold.clientes_segmentacao (
  id_cliente STRING COMMENT 'Identificador único do cliente (chave da tabela, uma linha por cliente).',
  nome_cliente STRING COMMENT 'Nome do cliente para exibição, em formato título e sem pronome de tratamento (Sr., Sra., Srta., Dr., Dra.).',
  estado STRING COMMENT 'Sigla da UF do cliente em maiúsculas (ex.: SP, MG).',
  nome_estado STRING COMMENT 'Nome completo do estado do cliente (ex.: São Paulo).',
  regiao STRING COMMENT 'Região do Brasil segundo o IBGE: Norte, Nordeste, Centro-Oeste, Sudeste ou Sul.',
  total_compras BIGINT COMMENT 'Quantidade de vendas (pedidos) do cliente no período. 0 para quem nunca comprou.',
  receita DECIMAL(10,2) COMMENT 'Receita total do cliente no período, em R$: soma de quantidade x preço unitário de todas as vendas, inclusive de produto não cadastrado. 0 para quem nunca comprou. Pode ser somada entre clientes.',
  ticket_medio DECIMAL(10,2) COMMENT 'Valor médio por venda do cliente, em R$ (média da receita por venda, arredondada em 2 casas). NULL para quem nunca comprou. Não some esta coluna; para ticket médio de um grupo use SUM(receita) / SUM(total_compras).',
  primeira_compra TIMESTAMP COMMENT 'Data e hora da primeira venda do cliente no período. NULL para quem nunca comprou.',
  ultima_compra TIMESTAMP COMMENT 'Data e hora da última venda do cliente no período. NULL para quem nunca comprou.',
  segmento_cliente STRING COMMENT 'Segmento pela receita no período: VIP (a partir de R$ 22.000), TOP_TIER (de R$ 17.000 até R$ 21.999,99) ou REGULAR (abaixo de R$ 17.000). Valores sempre em maiúsculas.',
  ranking_receita INT COMMENT 'Posição do cliente por receita, da maior para a menor (1 = cliente que mais gerou receita). Sem empates.'
)
COMMENT 'Use para saber quem são os melhores clientes, onde estão (estado e região) e em que segmento (VIP, TOP_TIER, REGULAR) cada um cai. Uma linha por cliente, inclusive quem nunca comprou (receita 0). Valores em R$ referentes ao período de 13/12/2025 a 11/01/2026, incluindo todas as vendas.'
AS
WITH compras AS (
  SELECT
    c.id_cliente,
    c.nome_cliente,
    c.estado,
    c.nome_estado,
    c.regiao,
    COUNT(v.id_venda) AS total_compras,
    CAST(COALESCE(SUM(v.receita), 0) AS DECIMAL(10,2)) AS receita,
    CAST(ROUND(AVG(v.receita), 2) AS DECIMAL(10,2)) AS ticket_medio,
    MIN(v.data_venda) AS primeira_compra,
    MAX(v.data_venda) AS ultima_compra
  FROM silver.clientes c
  LEFT JOIN silver.vendas v ON v.id_cliente = c.id_cliente
  GROUP BY c.id_cliente, c.nome_cliente, c.estado, c.nome_estado, c.regiao
)
SELECT
  id_cliente,
  nome_cliente,
  estado,
  nome_estado,
  regiao,
  total_compras,
  receita,
  ticket_medio,
  primeira_compra,
  ultima_compra,
  CASE
    WHEN receita >= 22000 THEN 'VIP'
    WHEN receita >= 17000 THEN 'TOP_TIER'
    ELSE 'REGULAR'
  END AS segmento_cliente,
  ROW_NUMBER() OVER (ORDER BY receita DESC, id_cliente) AS ranking_receita
FROM compras
