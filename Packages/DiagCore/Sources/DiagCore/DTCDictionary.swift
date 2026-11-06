import Foundation

/// French descriptions of standard SAE codes. Renault-specific codes and the
/// DFxxx names shown by CLIP are not public, so those fall back to a system label.
public enum DTCDictionary {
    private static let codes: [String: String] = [
        "P0100": "Débitmètre d'air : circuit", "P0101": "Débitmètre d'air : valeur incohérente",
        "P0102": "Débitmètre d'air : signal trop bas", "P0103": "Débitmètre d'air : signal trop haut",
        "P0105": "Capteur de pression d'admission : circuit", "P0106": "Capteur de pression d'admission : valeur incohérente",
        "P0107": "Capteur de pression d'admission : signal trop bas", "P0108": "Capteur de pression d'admission : signal trop haut",
        "P0110": "Température d'air d'admission : circuit", "P0112": "Température d'air d'admission : signal trop bas",
        "P0113": "Température d'air d'admission : signal trop haut", "P0115": "Température de liquide de refroidissement : circuit",
        "P0116": "Température de liquide de refroidissement : valeur incohérente", "P0117": "Température de liquide de refroidissement : signal trop bas",
        "P0118": "Température de liquide de refroidissement : signal trop haut", "P0120": "Capteur de pédale ou de papillon : circuit",
        "P0121": "Capteur de pédale ou de papillon : valeur incohérente", "P0122": "Capteur de pédale ou de papillon : signal trop bas",
        "P0123": "Capteur de pédale ou de papillon : signal trop haut", "P0130": "Sonde lambda amont : circuit",
        "P0133": "Sonde lambda amont : réponse lente", "P0135": "Sonde lambda amont : chauffage",
        "P0136": "Sonde lambda aval : circuit", "P0141": "Sonde lambda aval : chauffage",
        "P0170": "Richesse du mélange : défaut", "P0171": "Mélange trop pauvre",
        "P0172": "Mélange trop riche", "P0180": "Température de carburant : circuit",
        "P0190": "Capteur de pression de rampe : circuit", "P0191": "Capteur de pression de rampe : valeur incohérente",
        "P0192": "Capteur de pression de rampe : signal trop bas", "P0193": "Capteur de pression de rampe : signal trop haut",
        "P0200": "Injecteurs : circuit de commande", "P0201": "Injecteur cylindre 1 : circuit",
        "P0202": "Injecteur cylindre 2 : circuit", "P0203": "Injecteur cylindre 3 : circuit",
        "P0204": "Injecteur cylindre 4 : circuit", "P0219": "Surrégime moteur",
        "P0234": "Turbo : suralimentation excessive", "P0235": "Capteur de pression de turbo : circuit",
        "P0237": "Capteur de pression de turbo : signal trop bas", "P0238": "Capteur de pression de turbo : signal trop haut",
        "P0243": "Électrovanne de turbo : circuit", "P0245": "Électrovanne de turbo : signal trop bas",
        "P0246": "Électrovanne de turbo : signal trop haut", "P0299": "Turbo : suralimentation insuffisante",
        "P0300": "Ratés d'allumage : plusieurs cylindres", "P0301": "Ratés d'allumage : cylindre 1",
        "P0302": "Ratés d'allumage : cylindre 2", "P0303": "Ratés d'allumage : cylindre 3",
        "P0304": "Ratés d'allumage : cylindre 4", "P0325": "Capteur de cliquetis : circuit",
        "P0335": "Capteur de régime (vilebrequin) : circuit", "P0336": "Capteur de régime (vilebrequin) : signal incohérent",
        "P0340": "Capteur d'arbre à cames : circuit", "P0341": "Capteur d'arbre à cames : signal incohérent",
        "P0380": "Bougies de préchauffage : circuit", "P0382": "Bougies de préchauffage : circuit de commande",
        "P0400": "Vanne EGR : débit", "P0401": "Vanne EGR : débit insuffisant",
        "P0402": "Vanne EGR : débit excessif", "P0403": "Vanne EGR : circuit de commande",
        "P0404": "Vanne EGR : position incohérente", "P0405": "Capteur de position EGR : signal trop bas",
        "P0406": "Capteur de position EGR : signal trop haut", "P0420": "Catalyseur : efficacité insuffisante",
        "P0440": "Circuit d'évaporation : défaut", "P0443": "Électrovanne de purge du canister : circuit",
        "P0480": "Ventilateur de refroidissement : circuit", "P0500": "Capteur de vitesse véhicule : circuit",
        "P0501": "Capteur de vitesse véhicule : valeur incohérente", "P0505": "Régulation de ralenti : défaut",
        "P0560": "Tension batterie : défaut", "P0562": "Tension batterie trop basse",
        "P0563": "Tension batterie trop haute", "P0601": "Calculateur moteur : mémoire",
        "P0606": "Calculateur moteur : processeur", "P0670": "Boîtier de préchauffage : circuit",
        "P0700": "Boîte de vitesses : défaut signalé", "P1101": "Débitmètre d'air : valeur hors plage (constructeur)",
        "P2002": "Filtre à particules : efficacité insuffisante", "P2031": "Température de gaz d'échappement : circuit",
        "P2100": "Moteur de papillon : circuit", "P2122": "Capteur de pédale d'accélérateur 1 : signal trop bas",
        "P2123": "Capteur de pédale d'accélérateur 1 : signal trop haut", "P2127": "Capteur de pédale d'accélérateur 2 : signal trop bas",
        "P2128": "Capteur de pédale d'accélérateur 2 : signal trop haut", "P2135": "Capteurs de papillon ou de pédale : incohérence",
        "P2226": "Capteur de pression atmosphérique : circuit", "P242F": "Filtre à particules : colmaté par les cendres",
        "P2452": "Capteur de pression différentielle FAP : circuit", "P2453": "Capteur de pression différentielle FAP : valeur incohérente",
        "P2454": "Capteur de pression différentielle FAP : signal trop bas", "P2455": "Capteur de pression différentielle FAP : signal trop haut",
        "P2458": "Filtre à particules : régénération trop longue", "P2463": "Filtre à particules : accumulation de suies",
        "U0001": "Bus CAN : défaut de communication", "U0073": "Bus CAN : hors service",
        "U0100": "Communication perdue avec le calculateur moteur", "U0101": "Communication perdue avec la boîte de vitesses",
        "U0121": "Communication perdue avec l'ABS", "U0140": "Communication perdue avec l'UCH (habitacle)",
        "U0151": "Communication perdue avec l'airbag", "U0155": "Communication perdue avec le tableau de bord",
    ]

    public static func describe(_ code: String) -> String {
        if let known = codes[code] { return known }
        guard let letter = code.first else { return "Code inconnu" }
        switch letter {
        case "P": return "Défaut moteur ou transmission (détail dans la documentation Renault)"
        case "C": return "Défaut châssis : freins, direction, suspension"
        case "B": return "Défaut carrosserie : airbag, habitacle, confort"
        case "U": return "Défaut de communication entre calculateurs"
        default: return "Code inconnu"
        }
    }

    public static func failureType(_ value: UInt8) -> String {
        switch value {
        case 0x11: return "Court-circuit à la masse"
        case 0x12: return "Court-circuit au + batterie"
        case 0x13: return "Circuit ouvert"
        case 0x14: return "Court-circuit à la masse ou circuit ouvert"
        case 0x15: return "Court-circuit au + ou circuit ouvert"
        case 0x16: return "Tension trop basse"
        case 0x17: return "Tension trop haute"
        case 0x1C: return "Tension hors plage"
        case 0x21: return "Signal trop bas"
        case 0x22: return "Signal trop haut"
        case 0x29: return "Signal invalide"
        case 0x2F: return "Signal erratique"
        case 0x31: return "Pas de signal"
        case 0x4B: return "Température excessive"
        case 0x55: return "Non configuré"
        case 0x62: return "Signal incohérent"
        case 0x71: return "Actionneur bloqué"
        case 0x72: return "Actionneur bloqué ouvert"
        case 0x73: return "Actionneur bloqué fermé"
        case 0x87: return "Message manquant"
        case 0x92: return "Performance incorrecte"
        default: return String(format: "Type de panne %02X", value)
        }
    }
}
