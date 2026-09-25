# silver.clientes — cadastro de clientes padronizado (chave: id_cliente).
#
# PORQUÊ das regras:
# - Materialized view com leitura batch: a bronze é sobrescrita a cada ingestão.
# - Remove duplicatas por id_cliente: um cliente repetido duplicaria vendas em
#   qualquer join da gold.
# - nome_original guarda o nome como veio da origem, para auditoria; nome_cliente
#   é a versão para exibição: sem pronome de tratamento no início (Sr., Sra.,
#   Srta., Dr., Dra.), que não faz parte do nome e atrapalha ordenação e busca,
#   e em formato título.
# - estado (UF) em maiúsculas para casar com o mapeamento abaixo.
# - nome_estado e regiao vêm de um mapeamento fixo das 27 UFs do IBGE declarado
#   aqui mesmo, porque não existe tabela de estados na bronze. UF desconhecida
#   fica com regiao nula de propósito, para cair no fail.
# - Fail em id_cliente nulo ou regiao nula: sem chave não há como ligar vendas,
#   e sem região a análise regional ficaria incompleta sem ninguém perceber.

from itertools import chain

from pyspark import pipelines as dp
from pyspark.sql import functions as F

# UF -> (nome do estado, região) segundo o IBGE.
ESTADOS = {
    "AC": ("Acre", "Norte"),
    "AP": ("Amapá", "Norte"),
    "AM": ("Amazonas", "Norte"),
    "PA": ("Pará", "Norte"),
    "RO": ("Rondônia", "Norte"),
    "RR": ("Roraima", "Norte"),
    "TO": ("Tocantins", "Norte"),
    "AL": ("Alagoas", "Nordeste"),
    "BA": ("Bahia", "Nordeste"),
    "CE": ("Ceará", "Nordeste"),
    "MA": ("Maranhão", "Nordeste"),
    "PB": ("Paraíba", "Nordeste"),
    "PE": ("Pernambuco", "Nordeste"),
    "PI": ("Piauí", "Nordeste"),
    "RN": ("Rio Grande do Norte", "Nordeste"),
    "SE": ("Sergipe", "Nordeste"),
    "DF": ("Distrito Federal", "Centro-Oeste"),
    "GO": ("Goiás", "Centro-Oeste"),
    "MT": ("Mato Grosso", "Centro-Oeste"),
    "MS": ("Mato Grosso do Sul", "Centro-Oeste"),
    "ES": ("Espírito Santo", "Sudeste"),
    "MG": ("Minas Gerais", "Sudeste"),
    "RJ": ("Rio de Janeiro", "Sudeste"),
    "SP": ("São Paulo", "Sudeste"),
    "PR": ("Paraná", "Sul"),
    "RS": ("Rio Grande do Sul", "Sul"),
    "SC": ("Santa Catarina", "Sul"),
}

NOME_ESTADO = F.create_map(*[F.lit(x) for x in chain.from_iterable((uf, nome) for uf, (nome, _) in ESTADOS.items())])
REGIAO = F.create_map(*[F.lit(x) for x in chain.from_iterable((uf, regiao) for uf, (_, regiao) in ESTADOS.items())])

# Pronome de tratamento no início do nome, seguido de espaço.
PRONOME_TRATAMENTO = r"^(Sr|Sra|Srta|Dr|Dra)\.\s+"


@dp.materialized_view(
    name="silver.clientes",
    comment="Clientes sem duplicatas, nome sem pronome de tratamento, UF com nome do estado e região.",
)
@dp.expect_all_or_fail({
    "id_cliente_preenchido": "id_cliente IS NOT NULL",
    "regiao_preenchida": "regiao IS NOT NULL",
})
def clientes():
    uf = F.upper(F.trim("estado"))
    nome_sem_pronome = F.regexp_replace(F.trim("nome_cliente"), PRONOME_TRATAMENTO, "")

    return (
        spark.read.table("bronze.clientes")
        .dropDuplicates(["id_cliente"])
        .select(
            "id_cliente",
            F.col("nome_cliente").alias("nome_original"),
            F.initcap(nome_sem_pronome).alias("nome_cliente"),
            uf.alias("estado"),
            NOME_ESTADO[uf].alias("nome_estado"),
            REGIAO[uf].alias("regiao"),
            "pais",
            "data_cadastro",
        )
    )
