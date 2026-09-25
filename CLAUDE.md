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

## Regras para todo dashboard (AI/BI)

- Um arquivo por dashboard: `src/dashboards/<nome>.lvdash.json`, com o recurso em
  `resources/<nome>.dashboard.yml`: `warehouse_id: ${var.warehouse_id}` (variável com lookup do
  warehouse "Serverless Starter Warehouse"), `dataset_catalog: ${var.catalog}` e `dataset_schema: gold`.
- Consultas com o nome da tabela sem catálogo nem schema (`FROM vendas_temporais`), para o mesmo
  dashboard funcionar em dev e prod.
- Período fixo dos dados (13/12/2025 a 11/01/2026): nada de `current_date()`.
- Teste no warehouse TODAS as consultas que viram dataset antes do deploy.
- Tudo em português: título, subtítulo com período e fonte dos dados, nomes de gráficos e eixos.
  Canais exibidos como "E-commerce" e "Loja física". Dinheiro em R$.
- Layout de leitura rápida: título, uma linha de KPIs, gráficos e uma tabela de detalhe para agir.
- Ticket médio é receita total ÷ número de vendas, nunca média de médias: `SUM(receita) /
  SUM(total_vendas)` em vendas_temporais, `COUNT(*)` em vendas_detalhadas, `SUM(total_compras)` em
  clientes_segmentacao.
- Nunca somar `clientes_unicos` entre linhas. Produto se conta por `id_produto` (há nomes repetidos).
- Dia da semana se compara pela receita MÉDIA por dia: o período tem 5 sábados e 5 domingos e só 4
  de cada dia útil.
- Data e hora estão em UTC: diga isso no eixo.
- `diferenca_pct_*` está em pontos percentuais (10 = 10%): divida por 100 para usar o formato de %.
- Não crie campo calculado (`columns` do dataset) que seja só a soma de uma coluna, como
  `SUM(receita)`: o gráfico falha com "circular reference detected in calculated field". Use
  `SUM(\`receita\`)` direto no widget; campo calculado só para fórmulas (ticket médio, % VIP).
- Todo `fieldName` dos encodings precisa existir nos `fields` da consulta do widget.

## Regras para o Genie space (agente de IA)

- Um único space, "Diretoria E-commerce", para os três diretores, em cima das 5 golds (nada de
  bronze ou silver). Conteúdo em `src/genie/diretoria_ecommerce.geniespace.json` (serialized space
  exportado) e recurso em `resources/diretoria.genie_space.yml`: `warehouse_id: ${var.warehouse_id}`
  e `parent_path: ${workspace.root_path}`, para não colidir com outro space de mesmo nome.
- Mudou uma instrução? Edite o JSON e faça deploy. Nunca ajuste o space pela interface: se perde
  no próximo deploy.
- Os identificadores das tabelas estão escritos no JSON (`projetodados.gold.<tabela>`), porque o
  arquivo não passa por variáveis do bundle. Outro catálogo exige trocar no JSON.
- Não repita nas instruções o que o comentário da coluna já diz; instrução geral só para regra de
  negócio que não cabe em comentário (até ~2.500 caracteres).
- Conta em que a IA erra ganha SQL de exemplo, testado no warehouse, SEM repetir as perguntas do
  teste de aceitação (senão o teste vira cola).
- Toda mudança no space é conferida perguntando pela API de conversa do Genie e comparando com SQL
  direto na gold. Só é acerto se a resposta trouxer todos os números esperados.
- O botão "Ask Genie" dos 3 dashboards aponta para o space pelo id fixo no JSON do dashboard
  (`uiSettings.genieSpace.overrideId`, hoje o space de dev `01f1b91f35dc15fe8c08a2bdc9d9c7f2`).
  Em prod o space ganha outro id: troque o `overrideId` nos 3 JSONs ao publicar em prod.
- Placar de referência (dev, 25/09/2026): 10 de 10 perguntas do teste de aceitação certas, e as
  perguntas de limite ("Qual foi o nosso lucro?", "Quanto vendemos ontem?") recusadas sem SQL.

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
- Dashboards (sem filtro): Comercial com receita R$ 974.077,28, 3.020 vendas, ticket R$ 322,54 e
  4.322 itens (e-commerce: 2.155 vendas e R$ 705.486,21); Customer Success com 50 clientes, 10 VIP
  com 27,0% da receita, Norte como maior região (R$ 333.078,69); Pricing com 215 produtos, 20 mais
  caros que todos confirmados (R$ 161.375,09) e 15 com preço suspeito (todos de Tênis, sem venda,
  +100% vs. mercado); sem suspeitos, Beleza é a categoria mais cara (+1,24%).

@AGENTS.md
