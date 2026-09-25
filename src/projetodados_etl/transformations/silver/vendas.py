# silver.vendas — vendas limpas e enriquecidas (chave: id_venda).
#
# PORQUÊ das regras:
# - Materialized view com leitura batch: a bronze é sobrescrita a cada ingestão.
# - Remove duplicatas por id_venda: uma venda repetida inflaria a receita.
# - preco_unitario e receita (quantidade × preco_unitario) em DECIMAL(10,2):
#   dinheiro nunca em double, para a soma da receita bater ao centavo.
# - data, hora, dia_semana_num (1 = domingo ... 7 = sábado) e dia_semana em
#   português já prontos, para a gold agrupar por tempo sem refazer cálculo.
# - produto_cadastrado = false quando o id_produto não existe em silver.produtos,
#   e venda_antes_do_cadastro = true quando a venda é anterior à data_criacao do
#   produto. São problemas conhecidos da origem: MARCAMOS e medimos com warn,
#   nunca descartamos, porque apagar vendas mudaria a receita.
# - Fail nos campos obrigatórios, quantidade/preço positivos e canal válido:
#   isso nunca pode acontecer; se acontecer, a origem quebrou e o pipeline para.

from pyspark import pipelines as dp
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType

DIAS_SEMANA = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"]


@dp.materialized_view(
    name="silver.vendas",
    comment="Vendas sem duplicatas, com receita em DECIMAL(10,2), dimensões de tempo e marcações de qualidade.",
)
@dp.expect_all_or_fail({
    "id_venda_preenchido": "id_venda IS NOT NULL",
    "data_venda_preenchida": "data_venda IS NOT NULL",
    "id_cliente_preenchido": "id_cliente IS NOT NULL",
    "id_produto_preenchido": "id_produto IS NOT NULL",
    "quantidade_preenchida": "quantidade IS NOT NULL",
    "preco_unitario_preenchido": "preco_unitario IS NOT NULL",
    "quantidade_positiva": "quantidade > 0",
    "preco_unitario_positivo": "preco_unitario > 0",
    "canal_valido": "canal_venda IN ('ecommerce', 'loja_fisica')",
})
@dp.expect("produto_cadastrado", "produto_cadastrado")
@dp.expect("venda_depois_do_cadastro", "NOT venda_antes_do_cadastro")
def vendas():
    produtos = spark.read.table("silver.produtos").select("id_produto", "data_criacao")
    preco_unitario = F.col("preco_unitario").cast(DecimalType(10, 2))
    dia_semana_num = F.dayofweek("data_venda")

    return (
        spark.read.table("bronze.vendas")
        .dropDuplicates(["id_venda"])
        .join(produtos, "id_produto", "left")
        .select(
            "id_venda",
            "data_venda",
            F.to_date("data_venda").alias("data"),
            F.hour("data_venda").alias("hora"),
            dia_semana_num.alias("dia_semana_num"),
            F.element_at(F.array(*[F.lit(d) for d in DIAS_SEMANA]), dia_semana_num).alias("dia_semana"),
            "id_cliente",
            "id_produto",
            "canal_venda",
            "quantidade",
            preco_unitario.alias("preco_unitario"),
            (F.col("quantidade") * preco_unitario).cast(DecimalType(10, 2)).alias("receita"),
            F.col("data_criacao").isNotNull().alias("produto_cadastrado"),
            F.coalesce(F.col("data_venda") < F.col("data_criacao"), F.lit(False)).alias("venda_antes_do_cadastro"),
        )
    )
