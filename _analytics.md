Full Bug Investigation Report
Issue Summary
The analysis uncovered several issues ranging from critical memory leaks to minor logical inconsistencies. The most significant problems relate to unmanaged stream subscriptions, potential race conditions in state management, and inefficient data fetching patterns. Several pages are susceptible to runtime errors if the backend API or Firestore returns unexpected data structures.

Root Cause Analysis
Here is a detailed breakdown of each identified issue.

Issue #1: Critical Memory Leak in ChatScreen
File: d:\My Projects\pay_go\lib\pages\chat_screen.dart
Lines: 382-396
Severity: Critical
Root Cause: A StreamSubscription is created in \_startCall to listen for call status updates from Firestore. However, this subscription is never cancelled in the dispose method.
App Manifestation: This will cause a memory leak. Every time a user initiates a call from the ChatScreen, a new listener is attached to Firestore. Even after the user navigates away from the screen and the \_ChatScreenState is disposed, the subscription remains active in memory, continuing to receive data and preventing the state object from being garbage collected. This will lead to degraded app performance over time and can eventually cause a crash due to excessive memory consumption.
File Connections:
chat_screen.dart: The \_startCall method creates the subscription.
call_service.dart: The createCall method is used, but the issue is the handling of the stream after the call is created.
Issue #2: Critical Memory Leak in WebRTCHelper
File: d:\My Projects\pay_go\lib\services\webrtc_helper.dart
Lines: 159-165
Severity: Critical
Root Cause: A StreamSubscription is created in \_listenToCallSignals to listen for signaling data from the Firestore call document. The subscription is assigned to the local scope of the method, but it is never stored in a class-level variable. Consequently, there is no reference to cancel it in the dispose method.
App Manifestation: This is a severe memory leak. Every time a WebRTCHelper is initialized for a call, a Firestore listener is created and never removed. When the call ends and the CallScreen is closed, this listener will persist indefinitely, consuming memory and network resources. This will degrade app performance and can lead to crashes.
File Connections:
webrtc_helper.dart: The leak originates here.
call_screen.dart: This screen creates and disposes of WebRTCHelper, but it cannot fix the internal leak. The dispose call on \_webrtcHelper is correct, but the helper's own dispose method is incomplete.
Issue #3: Major Race Condition in ChatScreen AppBar
File: d:\My Projects\pay_go\lib\pages\chat_screen.dart
Lines: 177-183
Severity: Major
Root Cause: The build method of a widget should be pure and not have side effects. Inside the FutureBuilder's builder function, WidgetsBinding.instance.addPostFrameCallback is used to call setState. This is an improper use of setState within a build method. It can be called multiple times during a single frame, leading to race conditions, unnecessary rebuilds, and potential "setState() or markNeedsBuild() called during build" errors.
App Manifestation: The app might experience flickering in the AppBar title, performance issues due to excessive rebuilds, and in some Flutter versions, it will throw a runtime error, crashing the screen. The \_otherUserName might not be reliably set.
File Connections: This is a local logic error within chat_screen.dart.
Issue #4: Major Unhandled State in IncomingCallListener
File: d:\My Projects\pay_go\lib\widgets\incoming_call_listener.dart
Lines: 30-37
Severity: Major
Root Cause: The listenToIncomingCalls stream can emit a new call while a dialog for a previous call is already visible. The current logic checks if (ringingCall != null && \_currentCall == null), which correctly shows the first dialog. However, if a second call comes in, this condition is false, and nothing happens. If the first call is cancelled by the caller, the dialog is dismissed, but if the second call is still ringing, a new dialog is not re-triggered because the stream has already emitted the value.
App Manifestation: If a user receives a second call while the "Incoming Call" dialog for the first call is showing, they will not be notified of the second call. If the first caller hangs up, the dialog disappears, but the user is never shown the dialog for the second, still-ringing call, causing them to miss it entirely.
File Connections:
incoming_call_listener.dart: Contains the flawed listening logic.
call_service.dart: The listenToIncomingCalls stream provides the data that is being mishandled.
Issue #5: Major Inefficient Data Fetching in ChatListPage
File: d:\My Projects\pay_go\lib\pages\chat_list_page.dart
Lines: 135-220 (nested StreamBuilders)
Severity: Major
Root Cause: The widget uses two nested, independent StreamBuilders. The outer one listens to the chats collection, and the inner one listens to the users collection. The inner StreamBuilder fetches all users and then the code manually filters and sorts them based on the chat data. This is highly inefficient. As the number of users grows, this will fetch and process a huge amount of unnecessary data on the client, leading to high Firestore read costs and poor performance.
App Manifestation: The chat list page will become very slow to load and update as the user base grows. It will consume excessive device memory and battery, and incur significant, unnecessary Firebase costs.
File Connections: This is a design flaw within chat_list_page.dart.
Issue #6: Major Potential Crash in PostDetailPage
File: d:\My Projects\pay_go\lib\pages\post_detail_page.dart
Lines: 56-62
Severity: Major
Root Cause: The \_loadPost method fetches all posts from the API via \_apiService.getPosts(forceRefresh: true) and then uses .firstWhere to find the post with the matching postId. If the post has been deleted or the postId is invalid, .firstWhere with no orElse will throw a StateError.
App Manifestation: If a user tries to open a post that has been deleted (e.g., from a stale notification or a cached link), the PostDetailPage will crash with a StateError: No element, showing a red error screen to the user.
File Connections:
post_detail_page.dart: The .firstWhere call is the direct cause.
api_service.dart: The getPosts method provides the list to be searched.
notifications_page.dart: A user clicking a notification for a deleted post would trigger this crash.
Issue #7: Minor Logic Error in ChatScreen Call Cancellation
File: d:\My Projects\pay_go\lib\pages\chat_screen.dart
Lines: 45-53 (\_handleCallCancelled)
Severity: Minor
Root Cause: The \_handleCallCancelled method shows a SnackBar and then calls Navigator.of(context).popUntil((route) => route.isFirst). This is intended to dismiss the CallScreen if the user is on it. However, this logic is inside ChatScreen, not CallScreen. If the user has successfully navigated to the CallScreen, this code in ChatScreen will not execute in a way that affects the CallScreen. The StreamSubscription in \_startCall will remain active on the ChatScreen's state object, but its UI effects are misplaced.
App Manifestation: If a caller cancels a call while the callee's phone is ringing, the callee (who is on the CallScreen) will not see any notification that the call was cancelled. The CallScreen will remain, appearing to be stuck in a "ringing" state until the user manually closes it. The SnackBar will only appear if the user navigates back to the ChatScreen themselves.
File Connections:
chat_screen.dart: Contains the misplaced logic.
call_screen.dart: Is the screen that should be handling this state change, but isn't.
File Connection Map & Architecture Analysis
UI -> Service -> Firebase/API: The architecture follows a standard pattern where UI pages (e.g., FeedPage, ProfilePage) use a service (ApiService) to interact with the backend. This is good for separation of concerns.
Real-time Data: ChatScreen, ChatListPage, and IncomingCallListener interact directly with Firestore for real-time features. This is appropriate, but as noted, stream management is a recurring problem.
Authentication Flow: AuthGate correctly listens to FirebaseAuth.instance.authStateChanges() to direct users to either LoginOrRegisterPage or Homepage. This is a robust pattern.
State Management: State is managed locally within each StatefulWidget using setState. This is simple but becomes problematic with complex async operations, as seen in ChatScreen and FeedPage. For instance, FeedPage's \_postInteractions map is a form of local caching that could be better managed by a dedicated state management solution (like BLoC or Riverpod) to decouple UI from business logic and prevent race conditions.
Circular Dependencies: No direct circular dependencies were found at the import level.
Unused Imports/Providers: The codebase is generally clean of unused imports. Since it's not using a formal dependency injection or provider framework, there are no provider-related issues.
API Service (api_service.dart): This class acts as a singleton repository. It correctly centralizes API logic. However, its error handling is basic, often just re-throwing exceptions, leaving the UI layer to handle all error states. The caching logic for getPosts is invalidated on any mutation, which could be inefficient. A more granular cache update would be better.
Recommended Fix Order & Debugging Strategy
I recommend addressing the issues in order of severity to stabilize the application first.

webrtc_helper.dart (Issue #2 - Critical):

Action: Store the StreamSubscription in a class-level variable and cancel it in the dispose method. This is the most severe memory leak and affects a core feature.
File to Edit: d:\My Projects\pay_go\lib\services\webrtc_helper.dart
chat_screen.dart (Issue #1 - Critical):

Action: Similar to the above, store the call status StreamSubscription in a class-level variable and cancel it in the dispose method.
File to Edit: d:\My Projects\pay_go\lib\pages\chat_screen.dart
post_detail_page.dart (Issue #6 - Major):

Action: Modify the .firstWhere call to include an orElse: () => null and handle the null case gracefully (e.g., show a "Post not found" message instead of crashing).
File to Edit: d:\My Projects\pay_go\lib\pages\post_detail_page.dart
chat_screen.dart (Issue #3 - Major):

Action: Refactor the AppBar's FutureBuilder. The user data should be fetched once and stored in the state. The builder should only use the state variable. setState should not be called from within a build method.
File to Edit: d:\My Projects\pay_go\lib\pages\chat_screen.dart
chat_list_page.dart (Issue #5 - Major):

Action: This requires a larger refactor. Instead of fetching all users, fetch only the user profiles corresponding to the otherUserId from the chat documents. This can be done by iterating through chat docs, collecting user IDs, and then using a Firestore whereIn query to fetch only the necessary user profiles.
File to Edit: d:\My Projects\pay_go\lib\pages\chat_list_page.dart
incoming_call_listener.dart (Issue #4 - Major):

Action: The logic needs to handle a list of calls, not just the first one. When the stream emits, it should check if a dialog is already showing. If not, it should show a dialog for the first call in the list. When a dialog is dismissed (either by accepting, rejecting, or the call being cancelled), it should re-check the list of active calls and show the next one if available.
File to Edit: d:\My Projects\pay_go\lib\widgets\incoming_call_listener.dart
chat_screen.dart & call_screen.dart (Issue #7 - Minor):

Action: The call cancellation logic (\_handleCallCancelled) and its corresponding stream listener should be moved from ChatScreen to CallScreen. CallScreen is the active UI during a ringing call and is the correct place to manage its own lifecycle.
Files to Edit: d:\My Projects\pay_go\lib\pages\chat_screen.dart and d:\My Projects\pay_go\lib\pages\call_screen.dart.
This structured approach will resolve the most critical stability and performance issues first, providin
