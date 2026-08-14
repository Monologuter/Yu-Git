import Foundation

// 语法高亮放在 GitKit 里是个折中。
//
// 严格说它不属于「Git 操作与解析」，独立成包更干净。但它唯一的消费者是
// `FileDiff` 的渲染，而单开一个包要改 Xcode 工程加依赖，收益不抵风险。
// 等到第二个消费者出现（比如文件浏览器、代码片段预览），就该把
// `Syntax/` 整个搬进独立的 SyntaxKit——那时它的边界才真正清楚。

/// 一门语言的词法规则。
///
/// 刻意**只做词法，不做语法**：关键字、字符串、注释、数字这四类
/// 靠单遍扫描就能认出来，而且认错了最多是颜色不对，不影响读代码。
/// 真正的语法分析要建语法树，那是编译器的活，为了给 diff 上色不值当。
public struct Language: Sendable, Equatable {

    public let name: String
    /// 关键字。用 Set 而不是数组：每个词都要查一次，线性查找在长文件上很伤。
    public let keywords: Set<String>
    /// 单行注释的起始标记，例如 `//`、`#`。
    public let lineCommentMarkers: [String]
    /// 块注释的起止标记对。
    public let blockComment: (open: String, close: String)?
    /// 字符串的定界符。
    public let stringDelimiters: [Character]
    /// 字符串里的转义字符，nil 表示这门语言的字符串不支持转义。
    public let escapeCharacter: Character?

    public static func == (lhs: Language, rhs: Language) -> Bool { lhs.name == rhs.name }

    public init(
        name: String,
        keywords: Set<String>,
        lineCommentMarkers: [String],
        blockComment: (open: String, close: String)? = nil,
        stringDelimiters: [Character] = ["\"", "'"],
        escapeCharacter: Character? = "\\"
    ) {
        self.name = name
        self.keywords = keywords
        self.lineCommentMarkers = lineCommentMarkers
        self.blockComment = blockComment
        self.stringDelimiters = stringDelimiters
        self.escapeCharacter = escapeCharacter
    }
}

extension Language {

    /// 不认识的语言。词法为空，扫描器会原样返回纯文本。
    public static let plain = Language(name: "plain", keywords: [], lineCommentMarkers: [])

    public static let swift = Language(
        name: "Swift",
        keywords: [
            "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch",
            "class", "consuming", "continue", "default", "defer", "deinit", "do", "else", "enum",
            "extension", "fallthrough", "false", "fileprivate", "final", "for", "func", "guard",
            "if", "import", "in", "indirect", "init", "inout", "internal", "is", "isolated", "lazy",
            "let", "mutating", "nil", "nonisolated", "open", "operator", "package", "private",
            "protocol", "public", "repeat", "required", "rethrows", "return", "self", "Self",
            "some", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true",
            "try", "typealias", "var", "where", "while", "willSet", "didSet", "get", "set",
            "convenience", "override", "weak", "unowned", "borrowing", "each", "macro",
        ],
        lineCommentMarkers: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\""]
    )

    public static let javascript = Language(
        name: "JavaScript",
        keywords: [
            "abstract", "async", "await", "break", "case", "catch", "class", "const", "continue",
            "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "false",
            "finally", "for", "from", "function", "get", "if", "implements", "import", "in",
            "instanceof", "interface", "let", "new", "null", "of", "package", "private",
            "protected", "public", "readonly", "return", "satisfies", "set", "static", "super",
            "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void",
            "while", "with", "yield", "as", "declare", "namespace", "keyof", "infer",
        ],
        lineCommentMarkers: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'", "`"]
    )

    public static let python = Language(
        name: "Python",
        keywords: [
            "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
            "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import",
            "in", "is", "lambda", "match", "None", "nonlocal", "not", "or", "pass", "raise",
            "return", "self", "True", "try", "while", "with", "yield", "case",
        ],
        lineCommentMarkers: ["#"]
    )

    public static let go = Language(
        name: "Go",
        keywords: [
            "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
            "for", "func", "go", "goto", "if", "import", "interface", "map", "nil", "package",
            "range", "return", "select", "struct", "switch", "type", "var", "true", "false",
            "make", "new", "len", "cap", "append", "copy", "delete", "panic", "recover", "any",
        ],
        lineCommentMarkers: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "`"]
    )

    public static let rust = Language(
        name: "Rust",
        keywords: [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum",
            "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod",
            "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super",
            "trait", "true", "type", "unsafe", "use", "where", "while",
        ],
        lineCommentMarkers: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\""]
    )

    public static let java = Language(
        name: "Java",
        keywords: [
            "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class",
            "const", "continue", "default", "do", "double", "else", "enum", "extends", "final",
            "finally", "float", "for", "if", "implements", "import", "instanceof", "int",
            "interface", "long", "native", "new", "null", "package", "private", "protected",
            "public", "return", "short", "static", "strictfp", "super", "switch", "synchronized",
            "this", "throw", "throws", "transient", "true", "false", "try", "var", "void",
            "volatile", "while", "record", "sealed", "yield",
        ],
        lineCommentMarkers: ["//"],
        blockComment: ("/*", "*/")
    )

    public static let cLike = Language(
        name: "C",
        keywords: [
            "auto", "break", "case", "char", "const", "continue", "default", "do", "double",
            "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long",
            "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct",
            "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "class",
            "namespace", "template", "typename", "public", "private", "protected", "virtual",
            "nullptr", "true", "false", "new", "delete", "using", "constexpr", "noexcept",
            "@interface", "@implementation", "@property", "@end", "nil", "id", "BOOL",
        ],
        lineCommentMarkers: ["//"],
        blockComment: ("/*", "*/")
    )

    public static let ruby = Language(
        name: "Ruby",
        keywords: [
            "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else",
            "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next", "nil", "not",
            "or", "redo", "rescue", "retry", "return", "self", "super", "then", "true", "undef",
            "unless", "until", "when", "while", "yield", "require", "attr_accessor", "puts",
        ],
        lineCommentMarkers: ["#"]
    )

    public static let shell = Language(
        name: "Shell",
        keywords: [
            "if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "until", "do",
            "done", "function", "return", "local", "export", "readonly", "declare", "source",
            "echo", "exit", "set", "unset", "shift", "trap", "eval", "exec", "test",
        ],
        lineCommentMarkers: ["#"]
    )

    public static let json = Language(
        name: "JSON",
        keywords: ["true", "false", "null"],
        lineCommentMarkers: [],
        stringDelimiters: ["\""]
    )

    public static let yaml = Language(
        name: "YAML",
        keywords: ["true", "false", "null", "yes", "no", "on", "off"],
        lineCommentMarkers: ["#"]
    )

    public static let sql = Language(
        name: "SQL",
        keywords: [
            "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
            "CREATE", "TABLE", "ALTER", "DROP", "INDEX", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER",
            "ON", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "AND", "OR", "NOT", "NULL",
            "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "UNIQUE", "DEFAULT", "AS", "DISTINCT",
            "UNION", "CASE", "WHEN", "THEN", "ELSE", "END", "BEGIN", "COMMIT", "ROLLBACK",
        ],
        lineCommentMarkers: ["--"],
        blockComment: ("/*", "*/")
    )

    /// 按文件扩展名猜语言。
    ///
    /// 只看扩展名，不看内容。看内容（shebang、`<?php`）能多认出一些，
    /// 但 diff 里往往看不到文件开头那几行，判断依据本来就不全，
    /// 不如老实按扩展名来——猜错的代价只是没上色，而不是上错色。
    public static func detect(fromPath path: String) -> Language {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()

        // 有些文件全靠文件名认，没有扩展名
        switch name.lowercased() {
        case "makefile", "dockerfile", "gemfile", "rakefile", "podfile", "brewfile":
            return .shell
        case ".gitignore", ".gitattributes", ".env":
            return .shell
        default:
            break
        }

        switch ext {
        case "swift": return .swift
        case "js", "jsx", "mjs", "cjs", "ts", "tsx", "vue", "svelte": return .javascript
        case "py", "pyi", "pyw": return .python
        case "go": return .go
        case "rs": return .rust
        case "java", "kt", "kts", "gradle", "scala", "groovy": return .java
        case "c", "h", "cpp", "cc", "cxx", "hpp", "hh", "m", "mm", "cs": return .cLike
        case "rb", "gemspec", "podspec": return .ruby
        case "sh", "bash", "zsh", "fish", "ksh", "env": return .shell
        case "json", "json5", "jsonc": return .json
        case "yml", "yaml", "toml": return .yaml
        case "sql": return .sql
        default: return .plain
        }
    }
}
