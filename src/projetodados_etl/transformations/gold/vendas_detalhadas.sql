-- gold.vendas_detalhadas — uma linha por venda, com produto e cliente juntos.
--
-- PORQUÊ das regras:
-- - Serve às perguntas que cruzam diretorias ("receita por região e categoria",
--   "canal preferido dos VIPs") e aos filtros cruzados do dashboard, que
--   precisam de tempo, canal, produto e cliente na mesma linha.
-- - Grão = venda (id_venda único), igual a silver.vendas: os joins são LEFT e
--   por chave única (id_produto em silver.produtos, id_cliente em
--   gold.clientes_segmentacao), então não multiplicam nem perdem vendas.
-- - Produto não cadastrado continua na tabela (dinheiro que entrou é receita),
--   com os mesmos textos de gold.vendas_produtos: "Produto não cadastrado" no
--   nome e "Não cadastrado" em categoria, marca e faixa_preco.
-- - estado, regiao e segmento_cliente vêm de gold.clientes_segmentacao para a
--   segmentação ser exatamente a combinada com a diretoria de CS, sem repetir a
--   regra aqui. Não há COALESCE nesses campos: venda sem cliente conhecido deve
--   aparecer como NULL e ser pega pelo teste de qualidade.
-- - produto_cadastrado e venda_antes_do_cadastro repassam as marcações de
--   qualidade da silver, para quem analisa poder filtrar se quiser.
-- - CLUSTER BY (data): filtros de período são os mais comuns no dashboard.

CREATE OR REFRESH MATERIALIZED VIEW gold.vendas_detalhadas (
  id_venda STRING COMMENT 'Identificador único da venda (chave da tabela, uma linha por venda).',
  data_venda TIMESTAMP COMMENT 'Data e hora da venda.',
  data DATE COMMENT 'Data da venda (sem hora).',
  dia_semana STRING COMMENT 'Dia da semana da venda em português: Domingo, Segunda, Terça, Quarta, Quinta, Sexta ou Sábado. Para ordenar os dias, use dia_semana_num.',
  dia_semana_num INT COMMENT 'Número do dia da semana para ordenação: 1 = Domingo, 2 = Segunda ... 7 = Sábado.',
  hora INT COMMENT 'Hora do dia da venda, de 0 a 23.',
  canal_venda STRING COMMENT 'Canal da venda: ecommerce (loja online) ou loja_fisica. Valores sempre em minúsculas.',
  id_produto STRING COMMENT 'Identificador do produto vendido. Use para contar produtos distintos (há nomes de produto repetidos).',
  nome_produto STRING COMMENT 'Nome do produto. ATENÇÃO: produtos diferentes têm o mesmo nome; para contar produtos use id_produto. "Produto não cadastrado" quando o produto vendido não existe no cadastro.',
  categoria STRING COMMENT 'Categoria do produto. "Não cadastrado" quando o produto vendido não existe no cadastro.',
  marca STRING COMMENT 'Marca do produto. "Não cadastrado" quando o produto vendido não existe no cadastro.',
  faixa_preco STRING COMMENT 'Faixa pelo preço atual de cadastro: PREMIUM (acima de R$ 1.000), MEDIO (acima de R$ 500 até R$ 1.000) ou BASICO (até R$ 500). "Não cadastrado" quando o produto vendido não existe no cadastro.',
  id_cliente STRING COMMENT 'Identificador do cliente que comprou. Use COUNT(DISTINCT id_cliente) para contar clientes.',
  nome_cliente STRING COMMENT 'Nome do cliente para exibição, em formato título e sem pronome de tratamento.',
  estado STRING COMMENT 'Sigla da UF do cliente em maiúsculas (ex.: SP, MG).',
  regiao STRING COMMENT 'Região do Brasil do cliente segundo o IBGE: Norte, Nordeste, Centro-Oeste, Sudeste ou Sul.',
  segmento_cliente STRING COMMENT 'Segmento do cliente pela receita total dele no período (de gold.clientes_segmentacao): VIP (a partir de R$ 22.000), TOP_TIER (de R$ 17.000 até R$ 21.999,99) ou REGULAR (abaixo de R$ 17.000). Valores sempre em maiúsculas.',
  quantidade BIGINT COMMENT 'Unidades vendidas nesta venda.',
  preco_unitario DECIMAL(10,2) COMMENT 'Preço unitário praticado na venda, em R$.',
  receita DECIMAL(10,2) COMMENT 'Receita da venda em R$: quantidade x preço unitário. Pode ser somada entre linhas.',
  produto_cadastrado BOOLEAN COMMENT 'true se o produto existe no cadastro; false para produto vendido sem cadastro (problema conhecido da origem, a receita continua valendo).',
  venda_antes_do_cadastro BOOLEAN COMMENT 'true se a venda aconteceu antes da data de cadastro do produto (problema conhecido da origem, a receita continua valendo).'
)
CLUSTER BY (data)
COMMENT 'Use para perguntas que CRUZAM tempo, canal, produto e cliente, como receita por região e categoria ou canal preferido dos clientes VIP. Uma linha por venda, com todas as vendas (inclusive de produto não cadastrado); some receita e conte vendas com COUNT(*). Valores em R$ referentes ao período de 13/12/2025 a 11/01/2026. Para visões só por tempo/canal prefira gold.vendas_temporais; só por produto, gold.vendas_produtos; por cliente, gold.clientes_segmentacao.'
AS
SELECT
  v.id_venda,
  v.data_venda,
  v.data,
  v.dia_semana,
  v.dia_semana_num,
  v.hora,
  v.canal_venda,
  v.id_produto,
  COALESCE(p.nome_produto, 'Produto não cadastrado') AS nome_produto,
  COALESCE(p.categoria, 'Não cadastrado') AS categoria,
  COALESCE(p.marca, 'Não cadastrado') AS marca,
  COALESCE(p.faixa_preco, 'Não cadastrado') AS faixa_preco,
  v.id_cliente,
  c.nome_cliente,
  c.estado,
  c.regiao,
  c.segmento_cliente,
  v.quantidade,
  v.preco_unitario,
  v.receita,
  v.produto_cadastrado,
  v.venda_antes_do_cadastro
FROM silver.vendas v
LEFT JOIN silver.produtos p ON p.id_produto = v.id_produto
LEFT JOIN gold.clientes_segmentacao c ON c.id_cliente = v.id_cliente
