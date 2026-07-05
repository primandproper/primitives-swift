/// Sort direction for a list query, ported from platform-go's `filtering.SortAscending`/`SortDescending`.
///
/// Go models these as bare `*string` sentinels (`"asc"`/`"desc"`); Swift gets a proper closed enum, which
/// is both more idiomatic and self-validating on decode.
public enum SortDirection: String, Codable, Sendable {
  case ascending = "asc"
  case descending = "desc"
}
