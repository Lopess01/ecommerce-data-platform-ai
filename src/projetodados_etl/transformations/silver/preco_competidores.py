# silver.preco_competidores — preços coletados de concorrentes (chave: id_produto + nome_concorrente).
#
# PORQUÊ das regras:
# - Materialized view com leitura batch: a bronze é sobrescrita a cada ingestão.
# - Remove duplicatas por id_produto + nome_concorrente: cada concorrente tem um
#   preço por produto; repetições distorceriam médias de mercado.
# - preco_concorrente em DECIMAL(10,2): dinheiro nunca em double.
# - data_coleta chega como texto ('yyyy-MM-dd HH:mm:ss') e vira timestamp para
#   permitir filtros e ordenação por data.
# - preco_suspeito = true quando o concorrente cobra menos de 60% do nosso
#   preco_atual: provavelmente erro de coleta, produto diferente ou promoção
#   relâmpago. É um problema conhecido, então marcamos e medimos com warn
#   (preco_plausivel) em vez de descartar a linha.
# - Fail em id_produto nulo ou preço <= 0: são dados impossíveis, não suspeitos.

from pyspark import pipelines as dp
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType


@dp.materialized_view(
    name="silver.preco_competidores",
    comment="Preços de concorrentes sem duplicatas, com data de coleta em timestamp e marcação de preço suspeito.",
)
@dp.expect_all_or_fail({
    "id_produto_preenchido": "id_produto IS NOT NULL",
    "preco_positivo": "preco_concorrente > 0",
})
@dp.expect("preco_plausivel", "NOT preco_suspeito")
def preco_competidores():
    produtos = spark.read.table("silver.produtos").select("id_produto", "preco_atual")
    preco_concorrente = F.col("preco_concorrente").cast(DecimalType(10, 2))

    return (
        spark.read.table("bronze.preco_competidores")
        .dropDuplicates(["id_produto", "nome_concorrente"])
        .join(produtos, "id_produto", "left")
        .select(
            "id_produto",
            "nome_concorrente",
            preco_concorrente.alias("preco_concorrente"),
            F.to_timestamp("data_coleta", "yyyy-MM-dd HH:mm:ss").alias("data_coleta"),
            F.coalesce(preco_concorrente < F.col("preco_atual") * 0.6, F.lit(False)).alias("preco_suspeito"),
        )
    )
