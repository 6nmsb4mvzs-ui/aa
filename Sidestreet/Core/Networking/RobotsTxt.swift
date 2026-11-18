import Foundation

/// Minimal robots.txt evaluator (RFC 9309 subset: user-agent groups, Allow,
/// Disallow, longest-match precedence, `*` and `$` wildcards). Used before
/// reading a venue's public website for event listings.
struct RobotsTxt: Sendable, Hashable {
    struct Rule: Sendable, Hashable {
        var allow: Bool
        var pattern: String
    }

    private var groups: [(agents: [String], rules: [Rule])]

    static func == (lhs: RobotsTxt, rhs: RobotsTxt) -> Bool {
        lhs.groups.map(\.agents) == rhs.groups.map(\.agents) && lhs.groups.map(\.rules) == rhs.groups.map(\.rules)
    }

    func hash(into hasher: inout Hasher) {
        for group in groups {
            hasher.combine(group.agents)
            hasher.combine(group.rules)
        }
    }

    init(_ text: String) {
        var groups: [(agents: [String], rules: [Rule])] = []
        var currentAgents: [String] = []
        var currentRules: [Rule] = []
        var lastWasAgent = false
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
                .map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let colon = line.firstIndex(of: ":") else { continue }
            let field = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch field {
            case "user-agent":
                if !lastWasAgent && (!currentAgents.isEmpty || !currentRules.isEmpty) {
                    groups.append((currentAgents, currentRules))
                    currentAgents = []
                    currentRules = []
                }
                currentAgents.append(value.lowercased())
                lastWasAgent = true
            case "allow", "disallow":
                lastWasAgent = false
                guard !currentAgents.isEmpty else { continue }
                if field == "disallow" && value.isEmpty { continue } // "Disallow:" allows everything
                currentRules.append(Rule(allow: field == "allow", pattern: value))
            default:
                lastWasAgent = false
            }
        }
        if !currentAgents.isEmpty { groups.append((currentAgents, currentRules)) }
        self.groups = groups
    }

    /// Whether `path` may be fetched by a crawler identifying as `agentToken`.
    func isAllowed(path: String, agentToken: String) -> Bool {
        let token = agentToken.lowercased()
        let specific = groups.filter { group in group.agents.contains { $0 != "*" && token.contains($0) } }
        let applicable = specific.isEmpty ? groups.filter { $0.agents.contains("*") } : specific
        let rules = applicable.flatMap(\.rules)
        guard !rules.isEmpty else { return true }
        var best: Rule?
        var bestLength = -1
        for rule in rules where Self.matches(pattern: rule.pattern, path: path) {
            let length = rule.pattern.count
            if length > bestLength || (length == bestLength && rule.allow) {
                best = rule
                bestLength = length
            }
        }
        return best?.allow ?? true
    }

    static func matches(pattern: String, path: String) -> Bool {
        var pattern = pattern
        let anchored = pattern.hasSuffix("$")
        if anchored { pattern.removeLast() }
        let parts = pattern.components(separatedBy: "*")
        var searchStart = path.startIndex
        for (index, part) in parts.enumerated() {
            if part.isEmpty { continue }
            if index == 0 {
                guard path.hasPrefix(part) else { return false }
                searchStart = path.index(path.startIndex, offsetBy: part.count)
            } else {
                guard let range = path.range(of: part, range: searchStart..<path.endIndex) else { return false }
                searchStart = range.upperBound
            }
        }
        if anchored {
            if parts.last?.isEmpty == true { return true }
            return searchStart == path.endIndex
        }
        return true
    }
}
