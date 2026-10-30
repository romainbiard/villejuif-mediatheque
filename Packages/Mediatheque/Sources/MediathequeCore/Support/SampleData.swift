import Foundation

/// Données d'aperçu, cohérentes avec les maquettes (abonnée fictive Camille Martin).
public enum SampleData {
    static let calendar = BokehDates.parisCalendar

    static func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    public static let documents: [Notice] = [
        Notice(
            id: 745828, key: "HARRYPOTTERALECOLEDESSORCIERS--ROWLINGJ-1-GALLIMARDJEUNESSE-2023-1",
            title: "Harry Potter à l'école des sorciers", authors: ["Joanne Kathleen Rowling"], year: "2023",
            publisher: "Gallimard jeunesse", kind: .book, coverURL: nil, series: "Harry Potter", volume: "1",
            permalink: nil,
            harvestedCopies: [
                HarvestedCopy(library: .elsaTriolet, shelfMark: "SF ROW", barcode: "69372109"),
                HarvestedCopy(library: .pulpSud, shelfMark: "SF ROW", barcode: nil),
            ]
        ),
        Notice(
            id: 474169, key: "SWAY--TOTOG--IDOL-2018-3", title: "Sway", authors: ["Gérald Toto"], year: "2018",
            publisher: "Idol", kind: .cd, coverURL: nil, series: nil, volume: nil, permalink: nil,
            harvestedCopies: [HarvestedCopy(library: .elsaTriolet, shelfMark: "781.3 TOT", barcode: "69288593")]
        ),
        Notice(
            id: 871798, key: "TERRESDECINEMASURLESTRACESDEHARRYPOTTER--FROMENTJEAN---2017-ArteVod",
            title: "Terres de cinéma – Sur les traces de Harry Potter", authors: ["Jean Froment"], year: "2017",
            publisher: nil, kind: DocumentKind(code: "ArteVod", label: "Cinéma en ligne"), coverURL: nil,
            series: nil, volume: nil, permalink: nil, harvestedCopies: []
        ),
    ]

    public static let copies: [LiveCopy] = [
        LiveCopy(library: .elsaTriolet, libraryName: "Médiathèque Elsa-Triolet", status: .available, statusLabel: "Disponible",
                 section: "Jeunesse", location: "Pôle Littératures et langues", shelfMark: "SF ROW", holdCount: 0, pickupPath: nil),
        LiveCopy(library: .pulpNord, libraryName: "PULP Nord", status: .onLoan(dueDate: day(2026, 11, 17)), statusLabel: "En prêt",
                 section: "Jeunesse", location: nil, shelfMark: "SF ROW", holdCount: 2, pickupPath: "preview"),
    ]

    public static let patron = Patron(
        cardNumber: "0012345", firstName: "Camille", lastName: "MARTIN", email: "camille.martin@exemple.fr", phone: nil,
        homeLibrary: .pulpNord, cardExpiry: day(2027, 3, 14), cardExpired: false, cardAboutToExpire: false, cardExpiresInDays: 135,
        permissions: .init(blocked: false, loanForbidden: false, holdForbidden: false, digitalResourcesForbidden: false),
        counters: .init(loans: 4, lateLoans: 1, holds: 2, digitalLoans: 0, debts: 0, waitingToBePulled: 1),
        message: nil, hasUnreadMessage: false
    )

    public static let loans: [Loan] = [
        Loan(id: "100001_1", title: "Le Petit Prince", author: "Antoine de Saint-Exupéry", dueDate: day(2026, 10, 28),
             library: .elsaTriolet, libraryName: "Médiathèque Elsa-Triolet", recordID: nil, coverURL: nil),
        Loan(id: "100001_2", title: "Sway", author: "Gérald Toto", dueDate: day(2026, 11, 5),
             library: .elsaTriolet, libraryName: "Médiathèque Elsa-Triolet", recordID: 474169, coverURL: nil),
        Loan(id: "100001_3", title: "Chien pourri", author: "Colas Gutman", dueDate: day(2026, 11, 19),
             library: .pulpNord, libraryName: "PULP Nord", recordID: nil, coverURL: nil),
    ]

    public static let holds: [Hold] = [
        Hold(id: "100001_10", title: "Murmuration", author: "Sylvie Germain", statusText: "Disponible jusqu'au 06/11/2026",
             pickupLibrary: .elsaTriolet, pickupLibraryName: "Médiathèque Elsa-Triolet", recordID: 857057, coverURL: nil, rank: nil),
        Hold(id: "100001_11", title: "Astérix n° 39 · Astérix et le griffon", author: "Jean-Yves Ferri",
             statusText: "Pas disponible avant le 14/11/2026", pickupLibrary: .pulpNord, pickupLibraryName: "PULP Nord",
             recordID: 909376, coverURL: nil, rank: 1),
    ]

    public static let events: [Event] = [
        Event(id: 990, title: "Ronde des histoires", imageURL: nil, place: "Pulp Nord", library: .pulpNord,
              start: day(2026, 10, 31, 10, 30), end: day(2026, 10, 31, 11), isAllDay: false, type: "Lectures",
              audience: "Dès 4 ans", dateDescription: "Samedi 31 octobre 2026 de 10:30 à 11:00"),
        Event(id: 1019, title: "Conférence : IA - Comprendre les outils d’aujourd’hui", imageURL: nil,
              place: "Médiathèque Elsa-Triolet", library: .elsaTriolet, start: day(2026, 11, 4, 16), end: day(2026, 11, 4, 17),
              isAllDay: false, type: "Rencontre", audience: "Dès 13 ans", dateDescription: "Mercredi 4 novembre 2026 de 16:00 à 17:00"),
        Event(id: 983, title: "Prix des Lecteurs et Lectrices de Villejuif - Cap sur l’imaginaire !", imageURL: nil,
              place: nil, library: nil, start: day(2026, 9, 26), end: day(2027, 3, 27), isAllDay: true, type: nil,
              audience: nil, dateDescription: "Du samedi 26 septembre 2026 au samedi 27 mars 2027"),
    ]

    public static let libraries: [LibraryInfo] = [
        LibraryInfo(library: .elsaTriolet, slug: "elsa_triolet", name: "Médiathèque Elsa-Triolet",
                    addressLines: ["1 esplanade Pierre-Yves-Cosnier", "94800 Villejuif"], phone: "01 86 93 33 00", contactURL: nil,
                    hours: OpeningHours(lines: elsaHours), hourLines: elsaHours),
        LibraryInfo(library: .pulpNord, slug: "pulp_nord", name: "PULP Nord", addressLines: ["61 rue Pasteur", "94800 Villejuif"],
                    phone: "01 86 93 33 15", contactURL: nil, hours: OpeningHours(lines: pulpHours), hourLines: pulpHours),
        LibraryInfo(library: .pulpSud, slug: "pulp_sud", name: "PULP Sud", addressLines: ["118 rue Youri Gagarine", "94800 Villejuif"],
                    phone: "01 86 93 33 16", contactURL: nil, hours: OpeningHours(lines: pulpHours), hourLines: pulpHours),
    ]

    static let elsaHours = ["Mardi : 13h - 19h", "Mercredi : 10h - 19h", "Jeudi : 13h - 19h", "Vendredi : 13h - 19h", "Samedi : 10h - 18h"]
    static let pulpHours = ["Mardi : 15h - 19h", "Mercredi : 13h - 19h", "Vendredi : 15h - 19h", "Samedi : 10h - 18h"]
}
