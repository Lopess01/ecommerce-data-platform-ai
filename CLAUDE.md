# CLAUDE.md

Project guidance for AI agents lives in AGENTS.md and conventions below.

## Convenções do Projeto

- Catálogo `projetodados`, schemas `bronze`, `silver` e `gold`.
- Nomes de tabelas e colunas em português, `snake_case`, sem acento.
- Silver em Python (`from pyspark import pipelines as dp`), gold em SQL.
- Um arquivo por tabela: `transformations/silver/<tabela>.py` e `transformations/gold/<tabela>.sql`. Apague os exemplos que vieram no template.
- Todas as tabelas são materialized views com leitura batch (`spark.read.table`), nunca streaming table, porque a bronze é sobrescrita a cada execução.
- Pipeline serverless, catálogo `projetodados`, schema padrão `silver`. Golds publicadas como `gold.<tabela>`. Nomes no código sempre `schema.tabela`, sem catálogo.
- Cada arquivo começa com comentários explicando o PORQUÊ das regras, em português.
- Dinheiro sempre `DECIMAL(10,2)`.
- Problema de qualidade conhecido é MARCADO em uma coluna e medido com `@dp.expect` (warn). Nunca descarte linhas: apagar vendas mudaria a receita.
- `@dp.expect_all_or_fail` só para o que nunca pode acontecer.
- Sempre rode `databricks bundle validate --strict` antes do deploy.
- Sempre use o perfil de CLI "projetodados".

## Regras para toda gold

- SQL, um arquivo por tabela em `transformations/gold/`, com `CREATE OR REFRESH MATERIALIZED VIEW gold.<tabela>`.
- Declare TODAS as colunas entre parênteses com tipo e `COMMENT` (sem o tipo, o comentário é ignorado), e `COMMENT` na tabela dizendo quando usar a tabela.
- Comentários em português, com unidade (R$), regra de cálculo e avisos que evitem erro do Genie.
- O tipo declarado precisa bater com o da consulta: faça `CAST(... AS DECIMAL(10,2))` explícito em dinheiro agregado (`SUM`/`AVG` aumentam a precisão do decimal).
- Inclua TODAS as vendas, inclusive de produto não cadastrado: dinheiro que entrou é receita.
- Período dos dados: 13/12/2025 a 11/01/2026.
- Toda gold nova ganha testes no notebook `testes/testes_qualidade.py`.

## Números de referência (conferidos no Job em dev, 25/09/2026)

Depois de qualquer mudança, rode o Job e confira que estes números não mudaram
(a bronze é a mesma; se mudarem, alguma regra perdeu ou duplicou linhas).

- `silver.vendas`: 3.020 vendas, receita R$ 974.077,28; 2.155 no ecommerce e 865 na loja física.
- `gold.vendas_temporais`, `gold.vendas_produtos` e `gold.vendas_detalhadas`: mesmas 3.020 vendas e R$ 974.077,28.
- 20 vendas de produto não cadastrado, somando R$ 4.240,01 (20 produtos distintos, categoria "Não cadastrado").
- `silver.produtos`: 215 produtos (82 nomes repetidos: conte por `id_produto`); `gold.vendas_produtos`: 205 produtos vendidos.
- `gold.clientes_segmentacao`: 50 clientes, sendo 10 VIP, 25 TOP_TIER e 15 REGULAR.
- `gold.precos_competitividade`: 215 produtos, 35 MAIS_CARO_QUE_TODOS, 15 com preço suspeito
  (todos entre os mais caros que todos). Receita somada R$ 969.837,27: menor que o total porque
  as vendas de produto não cadastrado ficam fora. Não é tabela de receita total.

@AGENTS.md
