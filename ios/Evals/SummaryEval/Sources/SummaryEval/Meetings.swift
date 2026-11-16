import Foundation

/// Invented meetings. Each one has positions, agreements, an open question, a decision, and commitments with owners
/// and dates, so that every built-in template has something to find.
struct Meeting {
    let id: String
    let language: String
    let lines: [(speaker: String, text: String)]
    /// Facts that a good summary should carry. Checked loosely, case-insensitive, in any language of the line.
    let facts: [String]
}

private func parse(_ text: String) -> [(speaker: String, text: String)] {
    text.split(whereSeparator: \.isNewline).compactMap { sub -> (speaker: String, text: String)? in
        let line = String(sub)
        guard let colon = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }
        let after = line.index(after: colon)
        return (
            String(line[..<colon]).trimmingCharacters(in: .whitespaces),
            String(line[after...]).trimmingCharacters(in: .whitespaces),
        )
    }
}

enum Meetings {
    static let english = Meeting(id: "en", language: "en", lines: parse("""
    Ana: Thanks for joining. Today we need to decide whether we move the product launch from March to April.
    Bruno: I think we should move it. The payment flow still fails on older phones, about four percent of users.
    Carla: I disagree. Marketing already booked the ads for March tenth, and moving them costs us twelve thousand dollars.
    Ana: Twelve thousand is a lot. Bruno, how long would the fix take?
    Bruno: Two weeks for the fix, and one more week of testing.
    Carla: Then we could launch on March twenty-fourth instead of April, and keep most of the ad budget.
    Ana: That sounds like a fair middle ground. Does everyone agree with March twenty-fourth?
    Bruno: Yes, if the testing week is protected. No new features after March tenth.
    Carla: Agreed. I will ask the agency if they can move the ads by two weeks without a fee.
    Ana: Good. One thing we did not settle is whether we launch in Canada at the same time.
    Bruno: I have no idea what the tax rules there look like. We need someone from finance on that.
    Carla: I also wonder if the support team can handle two countries in the first month.
    Ana: Let us leave Canada open for now. Decision: the launch moves to March twenty-fourth, and features freeze on March tenth.
    Bruno: I will send the fix plan to everyone by Friday.
    Carla: And I will confirm the new ad dates with the agency by Wednesday.
    Ana: I will invite someone from finance to next week's meeting to talk about Canada.
    """), facts: ["24", "10", "12", "4"])

    static let portuguese = Meeting(id: "pt", language: "pt", lines: parse("""
    Marina: Bom dia, pessoal. Precisamos decidir hoje se reformamos a cozinha do escritório agora ou só no ano que vem.
    Pedro: Eu acho que tem que ser agora. A pia vaza toda semana e o fogão já pegou fogo uma vez em janeiro.
    Lucas: Eu entendo, mas o orçamento deste ano está apertado. A reforma completa custa uns quarenta mil reais.
    Marina: E se a gente fizer só o essencial agora? Trocar a pia e o fogão.
    Pedro: Isso resolve o perigo, mas a bancada também está quebrada.
    Lucas: Só a pia e o fogão saem por uns oito mil. Isso cabe no orçamento.
    Marina: Então estamos de acordo que a segurança vem primeiro?
    Pedro: Sim, nisso eu concordo totalmente.
    Lucas: Concordo também. A reforma completa fica para o orçamento do ano que vem.
    Pedro: Uma coisa que ninguém respondeu: quem limpa a cozinha depois da obra? A empresa de limpeza ou a gente?
    Marina: Boa pergunta. Eu não sei se o contrato da limpeza cobre isso.
    Lucas: E também não sabemos se a obra pode ser feita num fim de semana, para não atrapalhar ninguém.
    Marina: Decidido então: trocamos a pia e o fogão agora, com limite de oito mil reais.
    Lucas: Eu peço três orçamentos até sexta-feira.
    Pedro: Eu vejo o contrato da limpeza e trago a resposta na segunda.
    Marina: E eu apresento o plano da reforma completa para a diretoria em março.
    """), facts: ["8", "40", "sexta", "março"])

    static let japanese = Meeting(id: "ja", language: "ja", lines: parse("""
    佐藤：お疲れさまです。今日は新しい勤怠システムを来月から導入するかどうかを決めたいと思います。
    鈴木：私は賛成です。今の紙の申請だと、毎月の集計に三日かかっています。
    田中：私は少し心配です。現場のスタッフはスマホに慣れていない人も多いです。
    佐藤：導入費用はいくらでしたか。
    鈴木：初期費用が五十万円、月額が一人三百円です。
    田中：費用は問題ないと思いますが、説明会なしで始めるのは反対です。
    佐藤：では、説明会を開いてから導入するということで、皆さんよろしいですか。
    鈴木：はい、それなら賛成です。
    田中：私もそれなら大丈夫です。
    佐藤：一つ決まっていないのは、パートの方も対象にするかどうかです。
    田中：パートの方の契約にスマホの利用が含まれているか、確認が必要ですね。
    鈴木：それと、古いデータを移すかどうかもまだ決めていません。
    佐藤：決定します。導入は五月一日から、その前に説明会を二回開きます。
    鈴木：私が来週金曜日までに説明会の資料を作ります。
    田中：私は今月中にパートの方の契約を人事に確認します。
    佐藤：私はベンダーに五月一日開始で連絡します。
    """), facts: ["5", "50", "300", "2"])

    static let spanish = Meeting(id: "es", language: "es", lines: parse("""
    Lucía: Buenos días. Hoy tenemos que decidir si abrimos la tienda los domingos a partir de junio.
    Javier: Yo estoy a favor. Los sábados vendemos el doble que entre semana, y la gente pide abrir el domingo.
    Elena: Yo no lo tengo tan claro. El equipo ya trabaja seis días y nadie quiere más horas.
    Lucía: ¿Y si contratamos a dos personas solo para el fin de semana?
    Javier: Eso cuesta unos tres mil euros al mes, pero las ventas del domingo lo cubrirían.
    Elena: Si son personas nuevas y nadie del equipo actual pierde su descanso, me parece bien.
    Lucía: Entonces estamos de acuerdo en que nadie del equipo actual trabaja el domingo.
    Javier: De acuerdo.
    Elena: De acuerdo también.
    Javier: Lo que no sabemos es si el centro comercial abre el aparcamiento los domingos.
    Elena: Y tampoco sabemos si el permiso municipal cubre el domingo.
    Lucía: Decidido: abrimos los domingos desde el uno de junio, con dos personas nuevas.
    Elena: Yo publico la oferta de trabajo esta semana.
    Javier: Yo llamo al centro comercial el lunes para preguntar por el aparcamiento.
    Lucía: Y yo reviso el permiso con el ayuntamiento antes del quince de mayo.
    """), facts: ["1", "3", "15", "junio"])

    static let short = [english, portuguese, japanese, spanish]

    /// Long enough that the notes step runs: about 25 minutes of a Portuguese planning meeting.
    static let longPortuguese: Meeting = {
        let people = ["Marina", "Pedro", "Lucas", "Rafaela"]
        var lines: [(speaker: String, text: String)] = []
        for project in 1 ... 25 {
            let owner = people[project % 4]
            let other = people[(project + 1) % 4]
            let lead = people[(project + 2) % 4]
            lines += [
                (lead, "Próximo item é o projeto \(project). Como estamos?"),
                (other, "O projeto \(project) está no prazo, mas os preços subiram \(project % 9 + 2) por cento."),
                (lead, "Quanto do orçamento de \(project * 1000) reais já foi gasto?"),
                (other, "Mais ou menos a metade. Ainda falta pagar a segunda fase, e isso me preocupa um pouco."),
                (owner, "Falei com o fornecedor semana passada, e ele não vai baixar o preço este ano."),
                (lead, "Então aceitamos o preço novo e tiramos a diferença da reserva."),
                (other, "Eu concordo, desde que o financeiro aprove antes do fim do mês."),
                (
                    lead,
                    "Combinado. \(owner) manda o plano revisado do projeto \(project) até o dia \(project % 28 + 1).",
                ),
                (owner, "Pode deixar, eu mando o plano revisado do projeto \(project) até lá."),
                (other, "Ótimo. Não tenho mais nada sobre esse, podemos seguir."),
            ]
        }
        return Meeting(id: "pt-long", language: "pt", lines: lines, facts: ["1", "25"])
    }()
}
