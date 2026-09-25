# Databricks notebook source
# Testes de qualidade da camada silver.
#
# PORQUÊ: as expectations do pipeline olham linha a linha; estes testes olham a
# tabela inteira (chaves únicas, consistência da receita, proporção de vendas
# problemáticas). Cada teste é uma consulta que conta linhas com problema; se
# algum encontrar problema, o notebook falha com AssertionError e o Job fica
# vermelho, depois de mostrar a tabela com o resultado de todos os testes.

# COMMAND ----------

dbutils.widgets.text("catalogo", "projetodados")
catalogo = dbutils.widgets.get("catalogo")
silver = f"{catalogo}.silver"
gold = f"{catalogo}.gold"

# COMMAND ----------

testes = {
    "chave_unica_produtos": f"SELECT count(*) - count(DISTINCT id_produto) FROM {silver}.produtos",
    "chave_unica_clientes": f"SELECT count(*) - count(DISTINCT id_cliente) FROM {silver}.clientes",
    "chave_unica_preco_competidores": f"SELECT count(*) - count(DISTINCT id_produto, nome_concorrente) FROM {silver}.preco_competidores",
    "chave_unica_vendas": f"SELECT count(*) - count(DISTINCT id_venda) FROM {silver}.vendas",
    "receita_igual_quantidade_x_preco": f"""
        SELECT count(*) FROM {silver}.vendas
        WHERE receita <> CAST(quantidade * preco_unitario AS DECIMAL(10,2))
    """,
    # Vendas de produto não cadastrado são toleradas (ficam marcadas), mas acima
    # de 1% do total indicam que o cadastro de produtos quebrou.
    "produto_nao_cadastrado_abaixo_de_1pct": f"""
        SELECT CASE WHEN count_if(NOT produto_cadastrado) >= 0.01 * count(*)
                    THEN count_if(NOT produto_cadastrado) ELSE 0 END
        FROM {silver}.vendas
    """,
    # gold.clientes_segmentacao: a receita tem que fechar com a silver (nenhuma
    # venda pode se perder no LEFT JOIN), a chave é o cliente e o segmento só
    # pode ter os três valores combinados com a diretoria de CS.
    "gold_clientes_receita_igual_silver": f"""
        SELECT CASE WHEN (SELECT sum(receita) FROM {gold}.clientes_segmentacao)
                       = (SELECT sum(receita) FROM {silver}.vendas) THEN 0 ELSE 1 END
    """,
    "gold_clientes_id_cliente_unico": f"SELECT count(*) - count(DISTINCT id_cliente) FROM {gold}.clientes_segmentacao",
    "gold_clientes_segmento_valido": f"""
        SELECT count(*) FROM {gold}.clientes_segmentacao
        WHERE segmento_cliente IS NULL OR segmento_cliente NOT IN ('VIP', 'TOP_TIER', 'REGULAR')
    """,
    "gold_clientes_vip_a_partir_de_22000": f"""
        SELECT count(*) FROM {gold}.clientes_segmentacao
        WHERE segmento_cliente = 'VIP' AND receita < 22000
    """,
    # O Genie escreve SQL lendo os comentários: coluna sem comentário vira
    # chute. Tabelas __materialization* são internas do pipeline e ficam de fora.
    "gold_colunas_com_comentario": f"""
        SELECT count(*) FROM {catalogo}.information_schema.columns
        WHERE table_schema = 'gold'
          AND NOT startswith(table_name, '__materialization')
          AND (comment IS NULL OR trim(comment) = '')
    """,
}

resultados = [(nome, spark.sql(sql).first()[0]) for nome, sql in testes.items()]
resultados = [(nome, int(problemas), "OK" if problemas == 0 else "FALHOU") for nome, problemas in resultados]

display(spark.createDataFrame(resultados, "teste STRING, linhas_com_problema BIGINT, status STRING"))

# COMMAND ----------

falhas = [nome for nome, _, status in resultados if status == "FALHOU"]
assert not falhas, f"Testes de qualidade falharam: {', '.join(falhas)}"
