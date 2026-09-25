-- gold.precos_competitividade — Diretoria de Pricing: estamos mais caros que a
-- concorrência (Mercado Livre, Amazon, Magalu e Shopee) e em quais produtos agir?
--
-- PORQUÊ das regras:
-- - Uma linha por produto que tem preço de concorrente: JOIN (inner) de
--   silver.produtos com os preços agregados por produto, porque sem preço de
--   concorrente não há o que comparar. A receita entra por LEFT JOIN, para o
--   produto que nunca vendeu continuar na tabela com receita 0. Produto não
--   cadastrado não tem nosso preço, então fica fora: a soma da receita aqui é
--   menor que a total (é base de priorização, não de faturamento).
-- - nosso_preco é o preco_atual do cadastro; a média dos concorrentes é
--   arredondada em 2 casas e as diferenças são calculadas sobre ela, para os
--   números exibidos baterem entre si.
-- - diferenca_pct_* em pontos percentuais: 10 = nosso preço 10% mais caro,
--   -10 = 10% mais barato. Assim o Genie não confunde 0,10 com 10%.
-- - classificacao_preco segue esta ordem: primeiro os extremos (mais caro que
--   todos, mais barato que todos), porque são os casos de ação mais clara;
--   depois a posição em relação à média.
-- - Preço suspeito (concorrente abaixo de 60% do nosso preço, marcado na silver)
--   CONTINUA em todas as contas: promoção relâmpago existe e é preço real de
--   mercado. possui_preco_suspeito só alerta que o preço precisa ser confirmado
--   antes de reagir (baixar nosso preço por um erro de coleta sai caro).
-- - Dinheiro com CAST explícito para DECIMAL(10,2): SUM/AVG aumentam a precisão
--   do decimal e o tipo declarado precisa bater com o da consulta.

CREATE OR REFRESH MATERIALIZED VIEW gold.precos_competitividade (
  id_produto STRING COMMENT 'Identificador único do produto (chave da tabela, uma linha por produto com preço de concorrente). Use para contar produtos.',
  nome_produto STRING COMMENT 'Nome do produto. ATENÇÃO: produtos diferentes têm o mesmo nome; para contar ou agrupar produtos use id_produto.',
  categoria STRING COMMENT 'Categoria do produto.',
  marca STRING COMMENT 'Marca do produto.',
  nosso_preco DECIMAL(10,2) COMMENT 'Nosso preço atual de cadastro do produto, em R$.',
  preco_medio_concorrentes DECIMAL(10,2) COMMENT 'Preço médio dos concorrentes para o produto, em R$ (média simples, arredondada em 2 casas). Inclui preços suspeitos.',
  preco_minimo_concorrentes DECIMAL(10,2) COMMENT 'Menor preço entre os concorrentes para o produto, em R$. Inclui preços suspeitos.',
  preco_maximo_concorrentes DECIMAL(10,2) COMMENT 'Maior preço entre os concorrentes para o produto, em R$.',
  total_concorrentes BIGINT COMMENT 'Quantos concorrentes (de 1 a 4: Mercado Livre, Amazon, Magalu, Shopee) têm preço para o produto.',
  diferenca_pct_vs_media DECIMAL(10,2) COMMENT 'Quanto nosso preço está acima (+) ou abaixo (-) da média dos concorrentes, em pontos percentuais: 10 = 10% mais caro, -10 = 10% mais barato. Cálculo: (nosso_preco - preco_medio_concorrentes) / preco_medio_concorrentes x 100, arredondado em 2 casas. Não some; para um grupo use AVG.',
  diferenca_pct_vs_minimo DECIMAL(10,2) COMMENT 'Quanto nosso preço está acima (+) ou abaixo (-) do menor preço dos concorrentes, em pontos percentuais: 10 = 10% mais caro. Cálculo: (nosso_preco - preco_minimo_concorrentes) / preco_minimo_concorrentes x 100, arredondado em 2 casas. Não some; para um grupo use AVG.',
  classificacao_preco STRING COMMENT 'Posição do nosso preço, avaliada nesta ordem: MAIS_CARO_QUE_TODOS (acima do maior preço dos concorrentes), MAIS_BARATO_QUE_TODOS (abaixo do menor), ACIMA_DA_MEDIA, ABAIXO_DA_MEDIA ou NA_MEDIA (igual à média). Valores sempre em maiúsculas.',
  possui_preco_suspeito BOOLEAN COMMENT 'true se algum concorrente tem preço suspeito (abaixo de 60% do nosso preço: erro de coleta, produto diferente ou promoção relâmpago). O preço suspeito CONTINUA em todas as contas desta tabela; esta coluna só alerta que ele precisa ser confirmado antes de reagir.',
  receita DECIMAL(10,2) COMMENT 'Receita do produto no período de 13/12/2025 a 11/01/2026, em R$ (soma de quantidade x preço unitário). 0 se nunca vendeu. Use para priorizar os produtos em que agir. ATENÇÃO: a soma desta coluna NÃO é a receita total da empresa, pois só entram produtos com preço de concorrente (vendas de produto não cadastrado ficam fora); para receita total use gold.vendas_temporais.',
  itens_vendidos BIGINT COMMENT 'Unidades vendidas do produto no período de 13/12/2025 a 11/01/2026. 0 se nunca vendeu.'
)
COMMENT 'Use para saber se estamos mais caros ou mais baratos que a concorrência (Mercado Livre, Amazon, Magalu e Shopee) e em quais produtos agir: preços dos concorrentes, diferença percentual e classificação por produto, com a receita para priorizar. Uma linha por produto que tem preço de concorrente. Preços em R$ do cadastro atual; receita e itens do período de 13/12/2025 a 11/01/2026. Confirme preços com possui_preco_suspeito = true antes de reagir.'
AS
WITH concorrentes AS (
  SELECT
    id_produto,
    CAST(ROUND(AVG(preco_concorrente), 2) AS DECIMAL(10,2)) AS preco_medio_concorrentes,
    MIN(preco_concorrente) AS preco_minimo_concorrentes,
    MAX(preco_concorrente) AS preco_maximo_concorrentes,
    COUNT(*) AS total_concorrentes,
    MAX(preco_suspeito) AS possui_preco_suspeito
  FROM silver.preco_competidores
  GROUP BY id_produto
),
vendas AS (
  SELECT
    id_produto,
    SUM(receita) AS receita,
    SUM(quantidade) AS itens_vendidos
  FROM silver.vendas
  GROUP BY id_produto
)
SELECT
  p.id_produto,
  p.nome_produto,
  p.categoria,
  p.marca,
  p.preco_atual AS nosso_preco,
  c.preco_medio_concorrentes,
  c.preco_minimo_concorrentes,
  c.preco_maximo_concorrentes,
  c.total_concorrentes,
  CAST(ROUND((p.preco_atual - c.preco_medio_concorrentes) / c.preco_medio_concorrentes * 100, 2) AS DECIMAL(10,2)) AS diferenca_pct_vs_media,
  CAST(ROUND((p.preco_atual - c.preco_minimo_concorrentes) / c.preco_minimo_concorrentes * 100, 2) AS DECIMAL(10,2)) AS diferenca_pct_vs_minimo,
  CASE
    WHEN p.preco_atual > c.preco_maximo_concorrentes THEN 'MAIS_CARO_QUE_TODOS'
    WHEN p.preco_atual < c.preco_minimo_concorrentes THEN 'MAIS_BARATO_QUE_TODOS'
    WHEN p.preco_atual > c.preco_medio_concorrentes THEN 'ACIMA_DA_MEDIA'
    WHEN p.preco_atual < c.preco_medio_concorrentes THEN 'ABAIXO_DA_MEDIA'
    ELSE 'NA_MEDIA'
  END AS classificacao_preco,
  c.possui_preco_suspeito,
  CAST(COALESCE(v.receita, 0) AS DECIMAL(10,2)) AS receita,
  COALESCE(v.itens_vendidos, 0) AS itens_vendidos
FROM silver.produtos p
JOIN concorrentes c ON c.id_produto = p.id_produto
LEFT JOIN vendas v ON v.id_produto = p.id_produto
