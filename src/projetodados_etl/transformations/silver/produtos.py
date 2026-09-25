# silver.produtos — catálogo de produtos limpo (chave: id_produto).
#
# PORQUÊ das regras:
# - Materialized view com leitura batch: a bronze é sobrescrita a cada ingestão,
#   então recalculamos tudo a partir do estado atual (streaming table não serve).
# - Remove duplicatas por id_produto: vendas e preços de concorrentes fazem join
#   por essa chave; um produto repetido multiplicaria linhas e inflaria a receita.
# - trim em nome_produto: espaços sobrando quebram agrupamentos e buscas por nome.
# - preco_atual em DECIMAL(10,2): dinheiro nunca em double, para não acumular
#   erro de arredondamento em somas.
# - faixa_preco: segmentação usada pelo negócio (PREMIUM > 1000, MEDIO > 500,
#   BASICO no resto), calculada sobre o preço já em decimal.
# - Fail em id_produto nulo ou preco_atual <= 0: sem chave o produto não pode
#   ser ligado a nada, e preço zerado/negativo corromperia a comparação com
#   concorrentes. Isso nunca pode acontecer, então o pipeline para.

from pyspark import pipelines as dp
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType


@dp.materialized_view(
    name="silver.produtos",
    comment="Produtos sem duplicatas, com preço em DECIMAL(10,2) e faixa de preço.",
)
@dp.expect_all_or_fail({
    "id_produto_preenchido": "id_produto IS NOT NULL",
    "preco_atual_positivo": "preco_atual > 0",
})
def produtos():
    preco_atual = F.col("preco_atual").cast(DecimalType(10, 2))

    return (
        spark.read.table("bronze.produtos")
        .dropDuplicates(["id_produto"])
        .select(
            "id_produto",
            F.trim("nome_produto").alias("nome_produto"),
            "categoria",
            "marca",
            preco_atual.alias("preco_atual"),
            F.when(preco_atual > 1000, "PREMIUM")
            .when(preco_atual > 500, "MEDIO")
            .otherwise("BASICO")
            .alias("faixa_preco"),
            "data_criacao",
        )
    )
