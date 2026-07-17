/// An HTTP verb used by `APIRequest`.
public enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE", head = "HEAD"
}
