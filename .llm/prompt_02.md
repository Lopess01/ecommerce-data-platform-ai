# Prompt 2: o agente do Genie para os diretores

Agora os diretores vão perguntar sozinhos, em português. Crie um Genie space (agente do Genie)
chamado "Diretoria E-commerce", como código dentro deste bundle, em cima da gold. Use o perfil de
CLI e o catálogo do CLAUDE.md (catálogo projetoaovivo) e o warehouse "Serverless Starter Warehouse".

CONTEXTO
- O Genie não sabe nada da empresa: tudo o que ele sabe vem das tabelas, dos comentários das
  colunas e do que colocarmos no space. Os comentários da gold já existem; leia antes de escrever
  qualquer instrução e não repita nas instruções o que o comentário já diz.
- Um único space atende os três diretores: Comercial (vendas), Customer Success (clientes) e
  Pricing (preços da concorrência: Mercado Livre, Amazon, Magalu e Shopee).

CONVENÇÕES (grave nas instruções do projeto: o CLAUDE.md, ou o AGENTS.md que ele importa)
- O space fica em src/genie/diretoria_ecommerce.geniespace.json (o serialized space exportado) e o
  recurso em resources/diretoria.genie_space.yml, com o warehouse por lookup do nome e
  parent_path: ${workspace.root_path}, para não colidir com outro space de mesmo nome na sua pasta.
- Mudou uma instrução? Edite o JSON e faça deploy. Nada de ajustar o space pela interface, que se
  perde no próximo deploy.

O QUE VAI NO SPACE
- Tabelas: as 5 golds (vendas_temporais, vendas_produtos, vendas_detalhadas, clientes_segmentacao e
  precos_competitividade). Nenhuma tabela da bronze ou da silver.
- Instruções gerais, curtas (até uns 2.500 caracteres), só com regra de negócio que não cabe num
  comentário: responder em português; dinheiro em R$ com 2 casas; receita é bruta e não existe
  custo, margem ou lucro; o período vai de 13/12/2025 a 11/01/2026 e "no mês" ou "até agora" é o
  período inteiro, nunca current_date(); "hoje", "ontem" e "esta semana" não se respondem, porque
  11/01/2026 não é hoje: não gere SQL, explique o período em texto e pergunte se quer ver
  11/01/2026; qual tabela usar para cada tipo de pergunta (tempo e canal, produto, cliente, preço, e
  vendas_detalhadas para o que cruza diretorias); ticket médio = receita ÷ número de vendas
  (SUM(total_vendas) em vendas_temporais e vendas_produtos, COUNT(*) em vendas_detalhadas,
  SUM(total_compras) em clientes_segmentacao); contar produto por id_produto; dia da semana pela
  receita média por dia, citando também o dia de maior receita total e por que ele lidera; segmentos
  VIP (a partir de R$ 22.000), TOP_TIER (R$ 17.000 a R$ 21.999,99) e REGULAR; "mais caro que o
  mercado" = diferenca_pct_vs_media > 0 e "mais caro que todos" = MAIS_CARO_QUE_TODOS; toda contagem
  de produtos em precos_competitividade separa os confirmados dos que têm preço suspeito (a
  confirmar antes de reagir) e diz em que categoria estão os suspeitos, com o total; em "qual X
  vende mais", traga receita, número de vendas e ticket médio, e número de clientes (COUNT DISTINCT
  id_cliente) só em pergunta por região, estado ou segmento, nunca somando clientes_unicos; canais
  exibidos como "E-commerce" e "Loja física"; rankings com 10 linhas.
- Joins: vendas_produtos × precos_competitividade por id_produto (um para um) e
  vendas_detalhadas × clientes_segmentacao por id_cliente (muitos para um).
- SQL de exemplo (pergunta → SQL certo) para as contas em que a IA costuma errar, SEM repetir as
  perguntas do teste abaixo (senão o teste vira cola): ticket médio por segmento de cliente,
  participação dos TOP_TIER na receita, receita por região e categoria (vendas_detalhadas) e
  quantos produtos estão mais caros que a média do mercado, numa contagem com uma linha por
  situação (confirmado ou a confirmar), o total e as categorias dos suspeitos. Regra que falha em
  texto costuma passar com um SQL de exemplo no formato certo. Teste cada SQL no warehouse. Mais a
  medida "ticket médio" (de vendas_temporais) como SQL snippet.
- Sinônimos nas colunas: faturamento → receita, UF → estado, canal → canal_venda,
  perfil → segmento_cliente, posição de preço → classificacao_preco.
- 6 perguntas de exemplo na tela inicial, duas de cada diretoria, testadas: nenhuma pode voltar
  vazia.
- Os identificadores das tabelas ficam escritos no JSON (projetoaovivo.gold.<tabela>), porque o
  arquivo não passa por variáveis do bundle: anote isso nas instruções do projeto.

TESTE (é aqui que se ganha a confiança dos diretores)
Faça o deploy em dev e pergunte ao space pela API de conversa do Genie. Para cada pergunta, compare
a resposta com um SQL seu direto na gold e me mostre uma tabela: pergunta, resposta do Genie,
esperado, acertou? Só conta como acerto se a resposta trouxer todos os números do esperado.
1. Qual foi a receita total do período? → R$ 974.077,28
2. Qual canal vende mais? → E-commerce: 2.155 vendas, R$ 705.486,21, ticket R$ 327,37
3. Quais os 5 produtos que mais faturaram? → Fone de Ouvido Esportivo, Camisa Social, Necessaire,
   Persiana Vertical e Calça Jeans Skinny
4. Qual categoria gerou mais receita? → Moda, R$ 248.124,15
5. Quem são os 5 melhores clientes? → Ana Sophia Pereira (MG, R$ 30.716,63) em primeiro
6. Quantos clientes VIP temos e quanto representam da receita? → 10, R$ 262.806,22, 27,0%
7. Qual região gera mais receita? → Norte, R$ 333.078,69, 17 clientes
8. Qual dia da semana vende mais? → quarta-feira pela média por dia (R$ 34.753,61); sábado só
   pelo total, porque tem 5 no período
9. Quantos produtos estão mais caros que todos os concorrentes? → 35: 20 confirmados e 15 com preço
   suspeito a confirmar, todos de Tênis
10. Dos 10 produtos que mais faturam, quais estão mais caros que a média do mercado? → 5: Camisa
    Social, Persiana Vertical, Shorts Jeans, Vestido Floral e Notebook Inspiron 15
E duas perguntas de limite, que o Genie deve recusar sem inventar: "Qual foi o nosso lucro?" e
"Quanto vendemos ontem?".
Se errar, não mude o esperado: melhore o contexto do space (comentário, instrução, join ou SQL de
exemplo), faça o deploy e pergunte de novo, até acertar as 10. Registre o placar de cada rodada e
o que mudou entre elas: essa é a parte que mais ensina.

NO FIM
Ligue o botão "Ask Genie" dos 3 dashboards a este space (o id do space vai fixo no JSON do
dashboard: anote nas instruções do projeto que em prod ele muda), faça o deploy e me passe o link
do space e o placar final das perguntas.