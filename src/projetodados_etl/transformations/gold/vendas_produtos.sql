-- gold.vendas_produtos — Diretoria Comercial: quais produtos vendemos.
--
-- PORQUÊ das regras:
-- - Uma linha por produto vendido (id_produto de silver.vendas), com LEFT JOIN
--   em silver.produtos: vendas de produto não cadastrado continuam na tabela,
--   porque dinheiro que entrou é receita. Sem cadastro, nome vira "Produto não
--   cadastrado" e categoria, marca e faixa_preco viram "Não cadastrado", para o
--   produto aparecer nos agrupamentos em vez de sumir num NULL.
-- - Produtos diferentes têm o mesmo nome no cadastro (82 nomes repetidos), então
--   contar ou agrupar por nome_produto junta produtos distintos. A chave é
--   id_produto; o aviso vai no comentário para o Genie não errar.
-- - ticket_medio = ROUND(AVG(receita), 2): média da receita por venda do produto.
-- - ranking_receita e ranking_na_categoria usam ROW_NUMBER com desempate por
--   id_produto, para o ranking não ter empate e ser estável entre execuções.
-- - Dinheiro com CAST explícito para DECIMAL(10,2): SUM/AVG aumentam a precisão
--   do decimal e o tipo declarado precisa bater com o da consulta.

CREATE OR REFRESH MATERIALIZED VIEW gold.vendas_produtos (
  id_produto STRING COMMENT 'Identificador único do produto (chave da tabela, uma linha por produto vendido). Use esta coluna para contar produtos.',
  nome_produto STRING COMMENT 'Nome do produto. ATENÇÃO: produtos diferentes têm o mesmo nome; para contar ou agrupar produtos use id_produto, nunca nome_produto. "Produto não cadastrado" quando o produto vendido não existe no cadastro.',
  categoria STRING COMMENT 'Categoria do produto. "Não cadastrado" quando o produto vendido não existe no cadastro.',
  marca STRING COMMENT 'Marca do produto. "Não cadastrado" quando o produto vendido não existe no cadastro.',
  faixa_preco STRING COMMENT 'Faixa pelo preço atual de cadastro: PREMIUM (acima de R$ 1.000), MEDIO (acima de R$ 500 até R$ 1.000) ou BASICO (até R$ 500). "Não cadastrado" quando o produto vendido não existe no cadastro.',
  produto_cadastrado BOOLEAN COMMENT 'true se o produto existe no cadastro de produtos; false para produto vendido sem cadastro (problema conhecido da origem, a receita dele continua valendo).',
  total_vendas BIGINT COMMENT 'Quantidade de vendas (pedidos) do produto no período.',
  itens_vendidos BIGINT COMMENT 'Quantidade de unidades vendidas do produto no período (soma de quantidade).',
  receita DECIMAL(10,2) COMMENT 'Receita do produto no período, em R$: soma de quantidade x preço unitário das vendas. Pode ser somada entre produtos.',
  ticket_medio DECIMAL(10,2) COMMENT 'Valor médio por venda do produto, em R$ (média da receita por venda, arredondada em 2 casas). Não some esta coluna; para ticket médio de um grupo use SUM(receita) / SUM(total_vendas).',
  ranking_receita INT COMMENT 'Posição do produto por receita entre todos os produtos, da maior para a menor (1 = produto que mais gerou receita). Sem empates.',
  ranking_na_categoria INT COMMENT 'Posição do produto por receita dentro da sua categoria (1 = produto que mais gerou receita na categoria). Produtos não cadastrados são ranqueados juntos na categoria "Não cadastrado". Sem empates.'
)
COMMENT 'Use para perguntas sobre QUAIS PRODUTOS vendemos: receita, vendas, itens e ranking por produto, categoria, marca e faixa de preço. Uma linha por produto vendido, inclusive produto não cadastrado. Conte produtos por id_produto (há nomes repetidos). Valores em R$ referentes ao período de 13/12/2025 a 11/01/2026, incluindo todas as vendas. Para cruzar produto com cliente, região ou canal use gold.vendas_detalhadas.'
AS
WITH por_produto AS (
  SELECT
    v.id_produto,
    COALESCE(p.nome_produto, 'Produto não cadastrado') AS nome_produto,
    COALESCE(p.categoria, 'Não cadastrado') AS categoria,
    COALESCE(p.marca, 'Não cadastrado') AS marca,
    COALESCE(p.faixa_preco, 'Não cadastrado') AS faixa_preco,
    v.produto_cadastrado,
    COUNT(*) AS total_vendas,
    SUM(v.quantidade) AS itens_vendidos,
    CAST(SUM(v.receita) AS DECIMAL(10,2)) AS receita,
    CAST(ROUND(AVG(v.receita), 2) AS DECIMAL(10,2)) AS ticket_medio
  FROM silver.vendas v
  LEFT JOIN silver.produtos p ON p.id_produto = v.id_produto
  GROUP BY v.id_produto, p.nome_produto, p.categoria, p.marca, p.faixa_preco, v.produto_cadastrado
)
SELECT
  id_produto,
  nome_produto,
  categoria,
  marca,
  faixa_preco,
  produto_cadastrado,
  total_vendas,
  itens_vendidos,
  receita,
  ticket_medio,
  ROW_NUMBER() OVER (ORDER BY receita DESC, id_produto) AS ranking_receita,
  ROW_NUMBER() OVER (PARTITION BY categoria ORDER BY receita DESC, id_produto) AS ranking_na_categoria
FROM por_produto
