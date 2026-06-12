import AppKit

/// Lightweight syntax highlighting for the inspector's code previews — the
/// same zero-dependency approach as JSONPretty. Four token classes cover the
/// visual 80%: comments, strings, numbers and keywords. Not a grammar; a fast
/// single-pass scanner that never blocks (run off-main by the view).
enum CodeHighlight {

    struct Lang {
        var lineComment: [String] = []       // "//", "#", "--"
        var blockComment: (String, String)?  // ("/*", "*/")
        var stringDelims: Set<Character> = ["\"", "'"]
        var keywords: Set<String> = []
        var caseInsensitive = false          // SQL
    }

    /// Language for a file extension, or nil → no highlighting (plain text).
    nonisolated static func lang(for ext: String) -> Lang? {
        switch ext.lowercased() {
        case "sh", "bash", "zsh", "fish":
            return Lang(lineComment: ["#"], stringDelims: ["\"", "'", "`"], keywords: [
                "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
                "case", "esac", "function", "in", "local", "export", "return", "exit",
                "set", "source", "alias", "echo", "read", "shift", "break", "continue",
                "true", "false", "command", "eval", "exec", "trap"])
        case "js", "jsx", "mjs", "cjs", "ts", "tsx":
            return Lang(lineComment: ["//"], blockComment: ("/*", "*/"),
                        stringDelims: ["\"", "'", "`"], keywords: [
                "const", "let", "var", "function", "return", "if", "else", "for", "while",
                "do", "switch", "case", "default", "break", "continue", "new", "class",
                "extends", "import", "from", "export", "async", "await", "try", "catch",
                "finally", "throw", "typeof", "instanceof", "this", "null", "undefined",
                "true", "false", "interface", "type", "enum", "implements", "readonly",
                "public", "private", "protected", "static", "yield", "delete", "void", "of", "in"])
        case "java", "kt", "kts", "scala", "groovy":
            return Lang(lineComment: ["//"], blockComment: ("/*", "*/"), keywords: [
                "public", "private", "protected", "static", "final", "void", "int", "long",
                "double", "float", "boolean", "char", "byte", "short", "class", "interface",
                "extends", "implements", "return", "if", "else", "for", "while", "do",
                "switch", "case", "default", "break", "continue", "new", "try", "catch",
                "finally", "throw", "throws", "import", "package", "null", "true", "false",
                "this", "super", "abstract", "synchronized", "instanceof", "enum", "record",
                "var", "fun", "val", "when", "object", "data", "companion", "override",
                "lateinit", "suspend", "sealed"])
        case "swift":
            return Lang(lineComment: ["//"], blockComment: ("/*", "*/"), keywords: [
                "func", "let", "var", "if", "else", "guard", "for", "while", "repeat",
                "switch", "case", "default", "break", "continue", "return", "class",
                "struct", "enum", "protocol", "extension", "import", "init", "deinit",
                "self", "super", "nil", "true", "false", "try", "catch", "throw", "throws",
                "async", "await", "actor", "private", "public", "internal", "fileprivate",
                "static", "final", "lazy", "weak", "unowned", "some", "any", "in", "where",
                "defer", "typealias", "associatedtype", "inout", "mutating", "override"])
        case "py":
            return Lang(lineComment: ["#"], keywords: [
                "def", "return", "if", "elif", "else", "for", "while", "in", "not", "and",
                "or", "import", "from", "as", "class", "try", "except", "finally", "raise",
                "with", "lambda", "pass", "break", "continue", "None", "True", "False",
                "self", "yield", "async", "await", "global", "nonlocal", "is", "del", "assert", "match"])
        case "rb", "rake":
            return Lang(lineComment: ["#"], keywords: [
                "def", "end", "if", "elsif", "else", "unless", "while", "until", "for",
                "do", "return", "class", "module", "begin", "rescue", "ensure", "yield",
                "require", "include", "extend", "attr_accessor", "attr_reader", "nil",
                "true", "false", "self", "then", "case", "when", "break", "next", "lambda", "proc"])
        case "go":
            return Lang(lineComment: ["//"], blockComment: ("/*", "*/"),
                        stringDelims: ["\"", "'", "`"], keywords: [
                "func", "var", "const", "if", "else", "for", "range", "switch", "case",
                "default", "break", "continue", "return", "import", "package", "type",
                "struct", "interface", "map", "chan", "go", "defer", "select", "nil",
                "true", "false", "fallthrough", "goto", "make", "new", "len", "cap", "append"])
        case "rs":
            return Lang(lineComment: ["//"], blockComment: ("/*", "*/"), keywords: [
                "fn", "let", "mut", "if", "else", "for", "while", "loop", "match", "impl",
                "trait", "struct", "enum", "pub", "use", "mod", "return", "break",
                "continue", "self", "Self", "true", "false", "None", "Some", "Ok", "Err",
                "async", "await", "move", "ref", "where", "dyn", "Box", "Vec", "String",
                "unsafe", "crate", "super", "as", "in", "const", "static", "type"])
        case "c", "h", "m", "mm", "cpp", "cc", "cxx", "hpp", "hh":
            return Lang(lineComment: ["//"], blockComment: ("/*", "*/"), keywords: [
                "int", "char", "long", "short", "unsigned", "signed", "void", "float",
                "double", "struct", "union", "enum", "typedef", "static", "const", "if",
                "else", "for", "while", "do", "switch", "case", "default", "break",
                "continue", "return", "sizeof", "include", "define", "ifdef", "ifndef",
                "endif", "pragma", "class", "public", "private", "protected", "template",
                "typename", "namespace", "using", "new", "delete", "nullptr", "true",
                "false", "virtual", "override", "auto", "extern", "inline", "goto", "NULL"])
        case "css", "scss", "less":
            return Lang(blockComment: ("/*", "*/"), keywords: [
                "important", "media", "import", "keyframes", "supports", "font-face",
                "root", "hover", "focus", "active", "before", "after", "first-child",
                "last-child", "not", "inherit", "initial", "unset", "none", "auto", "var", "calc"])
        case "yaml", "yml", "toml", "ini", "conf", "env", "properties":
            return Lang(lineComment: ["#"], keywords: ["true", "false", "null", "yes", "no", "on", "off"])
        case "sql":
            return Lang(lineComment: ["--"], blockComment: ("/*", "*/"), keywords: [
                "select", "from", "where", "insert", "into", "values", "update", "set",
                "delete", "create", "table", "index", "view", "drop", "alter", "join",
                "left", "right", "inner", "outer", "on", "group", "by", "order", "having",
                "limit", "offset", "as", "and", "or", "not", "null", "in", "is", "like",
                "between", "exists", "union", "all", "distinct", "primary", "key",
                "foreign", "references", "default", "unique", "constraint", "begin",
                "commit", "rollback", "transaction"], caseInsensitive: true)
        default:
            return nil
        }
    }

    static let commentColor = NSColor.systemGray
    static let stringColor = NSColor.systemGreen
    static let numberColor = NSColor.systemOrange
    static let keywordColor = NSColor.systemPink

    /// Highlight `source` for `ext`, or nil when the extension has no language
    /// (caller falls back to the plain preview). Single pass over UTF-16.
    nonisolated static func highlight(_ source: String, ext: String, fontSize: CGFloat) -> NSAttributedString? {
        guard let lang = lang(for: ext) else { return nil }
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let out = NSMutableAttributedString(
            string: source,
            attributes: [.font: font, .foregroundColor: NSColor.textColor])
        let ns = source as NSString
        let n = ns.length

        func color(_ c: NSColor, _ from: Int, _ to: Int) {
            guard to > from else { return }
            out.addAttribute(.foregroundColor, value: c, range: NSRange(location: from, length: to - from))
        }
        func char(_ i: Int) -> unichar { ns.character(at: i) }
        func isWordChar(_ u: unichar) -> Bool {
            (u >= 97 && u <= 122) || (u >= 65 && u <= 90) || (u >= 48 && u <= 57) || u == 95 || u == 45
        }
        func startsWith(_ s: String, at i: Int) -> Bool {
            let len = (s as NSString).length
            guard i + len <= n else { return false }
            return ns.substring(with: NSRange(location: i, length: len)) == s
        }

        var i = 0
        while i < n {
            let u = char(i)
            let scalar = Unicode.Scalar(u)

            // Line comments — but "#" only when it starts a comment, not #!/usr/bin
            // (shebangs are comments too; fine to gray them).
            if let cmt = lang.lineComment.first(where: { startsWith($0, at: i) }) {
                var j = i + (cmt as NSString).length
                while j < n, char(j) != 10 { j += 1 }
                color(commentColor, i, j)
                i = j
                continue
            }
            if let (open, close) = lang.blockComment, startsWith(open, at: i) {
                var j = i + (open as NSString).length
                while j < n, !startsWith(close, at: j) { j += 1 }
                j = min(j + (close as NSString).length, n)
                color(commentColor, i, j)
                i = j
                continue
            }
            if let s = scalar, lang.stringDelims.contains(Character(s)) {
                let quote = u
                var j = i + 1
                while j < n {
                    if char(j) == 92 { j += 2; continue }      // backslash escape
                    if char(j) == quote { break }
                    if char(j) == 10, quote != 96 { break }    // strings end at EOL (not backticks)
                    j += 1
                }
                let end = min(j + 1, n)
                color(stringColor, i, end)
                i = end
                continue
            }
            if u >= 48 && u <= 57 {                            // number
                var j = i
                while j < n, isWordChar(char(j)) || char(j) == 46 { j += 1 }
                color(numberColor, i, j)
                i = j
                continue
            }
            if isWordChar(u), !(u >= 48 && u <= 57) {          // identifier / keyword
                var j = i
                while j < n, isWordChar(char(j)) { j += 1 }
                let word = ns.substring(with: NSRange(location: i, length: j - i))
                let probe = lang.caseInsensitive ? word.lowercased() : word
                if lang.keywords.contains(probe) { color(keywordColor, i, j) }
                i = j
                continue
            }
            i += 1
        }
        return out
    }
}
