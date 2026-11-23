import GraniteAgents

/// The quill agent's place in Granite's roster: an app that links this package finds the `quill` agent by this record,
/// with nothing listed by hand.
@used @section("__DATA_CONST,__granite")
let quillRecord: GraniteRoster.Record = { GraniteRoster.record(QuillAgent.self) }
