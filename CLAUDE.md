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

@AGENTS.md
