# Privacidade

[English](PRIVACY.md) · [日本語](PRIVACY.ja.md) · Português · [Español](PRIVACY.es.md)

Esta página explica em linguagem simples o que o código faz. A própria compilação garante a maior parte disso: veja `Tools/check-privacy` e `Tools/privacy-allowlist.json`. Se houver diferença entre esta tradução e a [versão em inglês](PRIVACY.md), vale a versão em inglês.

## O que sai do seu aparelho

Nada do que você grava, digita ou pergunta. Gravação, transcrição, identificação de quem fala, resumos e conversas rodam todos no aparelho.

O app faz dois tipos de conexão. O segundo é opcional e fica desligado até você configurar.

1. **Downloads de modelos de IA que você inicia.** Vêm do Hugging Face, em versões fixas e com hash verificado. Ajustes > Atividade de rede lista cada um, com data, endereço e tamanho. Você pode limpar essa lista; depois disso, a tela avisa que o histórico foi limpo, em vez de dizer que nada saiu.

O iOS pode baixar os próprios modelos de idioma para o Apple Speech e para a busca. Quem faz isso é o iOS, não o app, e nenhum conteúdo de reunião está envolvido.

2. **Conectores que você pareia.** Se você conectar o Get Things Done, as novas reuniões vão para aquele único computador, na sua própria rede, criptografadas para ele. Por padrão, só o áudio vai. Transcrições e fotos têm cada uma o seu próprio botão. Nada passa pela internet, e cada envio aparece em Atividade de rede.

## O que o app não tem

Sem contas. Sem analytics. Sem serviço de relatório de falhas. Sem publicidade. Sem servidor.

## O que fica no aparelho, e onde

| Dado | Onde | Entra no backup do iOS? |
|---|---|---|
| Gravações, transcrições, resumos, conversas, memória, impressões de voz | Armazenamento privado do app | Não, a menos que você ative em Armazenamento e backup |
| Modelos de IA | Armazenamento privado do app | Nunca |
| Próximo evento e nomes de reuniões recentes | Um arquivo compartilhado com o widget do app | Não. Só é gravado se você ativar "Mostrar nomes de reuniões nos widgets", e é apagado quando você desativa |

Se você ativar o backup, suas gravações seguem as configurações de backup do seu iPhone, o que pode significar o iCloud.

## Seus controles

- **Bloquear o app:** pede Face ID ou o código, e esconde o conteúdo no alternador de apps.
- **Exportar a biblioteca:** um único arquivo protegido pela sua senha (AES-256-GCM). Sem a senha, ninguém consegue abrir, e não há como recuperá-la. As impressões de voz ficam de fora, a não ser que você as inclua.
- **Apagar uma gravação:** remove o áudio, a transcrição, os resumos, os dados de busca, as conversas sobre ela e qualquer resposta que a cite.
- **Apagar tudo:** remove tudo isso, mais os modelos e os ajustes. Os modelos de idioma do próprio iOS ficam, já que pertencem ao iOS.

## Impressões de voz

Impressões de voz são dados biométricos. São opcionais, precisam do seu consentimento para cada pessoa e podem ser apagadas em Pessoas.

## Gravar outras pessoas

Gravar pessoas pode exigir o consentimento delas, dependendo de onde você está. Isso é responsabilidade sua, e o app lembra você antes da primeira gravação.

## Os limites, com honestidade

- A IA pode errar. Resumos e respostas levam às fontes para você conferir.
- Quem consegue desbloquear seu celular consegue abrir o app, a menos que você ative o bloqueio do app.
