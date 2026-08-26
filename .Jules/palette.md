## 2024-10-24 - Declarative Focus Management for tvOS
**Learning:** Imperative focus management (assigning true to @FocusState inside .onAppear or .task, especially with DispatchQueue delays) often conflicts with the tvOS Focus Engine, causing glitches or missed focus events.
**Action:** Always use SwiftUI's declarative `.defaultFocus($state, condition)` modifier instead of imperative lifecycle assignments to ensure the Focus Engine can natively prioritize and manage initial focus correctly.
