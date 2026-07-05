/// # Notifications
///
/// Ported from platform-go's `notifications` package — but only the **mobile push** slice
/// (`notifications/mobile`), per the iOS-only scope of this port (see `PORTING.md`). `notifications/async`
/// (Ably/Pusher/SSE/WebSocket realtime broadcast dispatch) is a server-side pub/sub concern with no iOS
/// analogue and is dropped entirely.
///
/// ## What ships
///
/// * ``PushNotificationSender`` — the provider-agnostic protocol a push-sending backend implements,
///   ported from Go's `mobile.PushNotificationSender`.
/// * ``PushMessage`` — the message content (title/body/optional badge count), ported from
///   `mobile.PushMessage`.
/// * ``MobileNotificationRequest`` — the generic mobile-push job payload, ported from
///   `mobile.MobileNotificationRequest`, wire-compatible with Go's JSON keys.
/// * ``NoopPushNotificationSender`` / ``MockPushNotificationSender`` — test doubles, ported from
///   `mobile/noop` (the mock is new: Go has no generated mock for this interface, but a recording one is
///   straightforward and useful for a client app's own test suite).
/// * ``NotificationsConfig`` / ``APNsConfig`` / ``FCMConfig`` / ``PushProvider`` — the provider-seam
///   config, ported from `mobile/config`.
///
/// ## What is intentionally NOT ported (the salsa20 treatment)
///
/// Actually *sending* a push via APNs (token auth, HTTP/2 to Apple) or FCM (the Firebase Admin SDK) is a
/// server concern: an iOS app receives push notifications through the OS, it never sends its own. So,
/// exactly like ``Cryptography``'s `salsa20` case:
///
/// * ``APNsConfig`` and ``FCMConfig`` still **decode** — a Go-authored `NotificationsConfig` JSON
///   payload never fails to parse on this platform.
/// * ``NotificationsConfig/makePushSender()`` **throws** ``NotificationsError/unsupportedProvider(_:)``
///   for ``PushProvider/apnsFCM``, rather than silently degrading to a noop that would report every send
///   as a success.
///
/// `mobile/apns` (the `sideshow/apns2` token-auth client) and `mobile/fcm` (the Firebase Admin SDK
/// client) are consequently not ported at all — there is no Swift type standing in for `apns.Sender` /
/// `fcm.Sender`; both would pull in heavy, server-oriented dependencies with no client-side use.
///
/// ## Dropped (server-side, no analogue)
///
/// * `notifications/async` (`ably`, `pusher`, `sse`, `websocket`, `config`) — realtime broadcast dispatch
///   from a server to many subscribers. See `PORTING.md`'s remaining-work list for `eventstream`, the
///   client-*consumer* side of a similar shape.
/// * `mobile.MultiPlatformPushSender` — the routing shell that composed `apns.Sender` + `fcm.Sender` by
///   platform. Once both backends are salsa20'd out, the router has nothing left to route between: its
///   one portable behavior (platform-string normalization plus a "sender not configured" error) collapses
///   into ``NotificationsConfig/makePushSender()`` simply returning a single sender that already handles
///   every platform (``NoopPushNotificationSender`` today, until a real backend is wired up).
public enum Notifications {}
