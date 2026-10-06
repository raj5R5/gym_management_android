# Development Instructions

## 1. Project Purpose

`gym_management_app` is a production-oriented Gym Management System for Android and iOS, not a tutorial or demo application. The application will eventually support Admin, Trainer, and Member roles.

The planned technology stack is Flutter and Dart, Riverpod for state management, a REST API provided by a Node.js + Express backend, MongoDB, JWT authentication, and secure token storage on the Flutter client. These are planned choices, not a claim that they are already implemented or installed.

## 2. Development Principles

- Prefer maintainable, readable, production-quality code.
- Follow separation of concerns and avoid unnecessary complexity.
- Introduce dependencies only when there is a clear reason.
- Do not duplicate logic. Reuse existing services, models, providers, widgets, and utilities where appropriate.
- Never make large architectural changes without explicit approval.

## 3. Flutter Architecture

The planned architecture will separate core functionality, features, models, services, providers/state management, and reusable widgets.

The final folder structure will be finalized separately. Do not invent or create it based solely on this document. Inspect the existing implementation and follow the approved architecture when it is established.

## 4. State Management

Riverpod is the chosen state-management solution. Do not introduce another state-management framework unless explicitly approved.

## 5. Networking

- Isolate REST API communication from UI code.
- Do not make raw HTTP/API calls directly from widgets unless explicitly justified.
- Reuse existing networking services and keep request, response, and API error handling separate from presentation concerns.

## 6. Authentication

The eventual authentication system will use the Node.js + Express backend, MongoDB, JWT, and secure storage for tokens on the Flutter client.

- Never hardcode secrets, JWT signing secrets, passwords, API keys, or database credentials.
- Store authentication tokens in secure storage rather than ordinary preferences or source code.
- Do not log tokens, passwords, or other sensitive authentication data.

## 7. Security

- Never commit secrets or place production credentials in source code.
- Validate user input; client validation does not replace server validation.
- Handle authentication and authorization separately. Enforce permissions for Admin, Trainer, and Member on the backend; UI visibility alone is not authorization.
- Do not weaken security to make a feature work.

## 8. Error Handling

- Handle loading, success, empty, and error states where appropriate.
- Do not silently swallow exceptions.
- Present useful error messages without exposing sensitive details.

## 9. Testing

- Add appropriate tests for new important business logic.
- Do not delete or weaken existing tests just to make the test suite pass.
- Update tests when intended behavior changes, preserving meaningful coverage.

## 10. Git

- Keep changes focused and do not modify unrelated files.
- Before making a large change, explain what will be changed.
- Prefer small, logical commits after successful validation, within the user's authorized scope.
- Preserve existing user changes and never include secrets in commits.

## 11. AI Agent Behavior

Before implementing a task:

- Inspect the relevant existing code.
- Understand the current architecture.
- Identify dependencies and affected components.
- Explain any important assumptions.

Do not:

- Rewrite unrelated code.
- Delete working code without justification.
- Introduce unnecessary packages.
- Create duplicate services, models, or providers.
- Change architecture without approval.
- Modify Android or iOS configuration unless the task requires it.

Follow the user's task scope. This document does not authorize creating architecture, installing dependencies, or implementing features without a corresponding task.

## 12. Validation

After implementation, run the appropriate checks for the change:

- `flutter analyze`
- `flutter test`
- Relevant build or test commands, such as `flutter build apk --debug` for Android changes and an appropriate iOS build when the environment supports it.

Report failures honestly, including the exact failure, whether it is a project or environment problem, and the recommended fix. Clearly state which checks were run and which were not. Do not claim validation succeeded when it was skipped or failed.

## 13. Important Workflow

For every significant feature, follow:

Requirements → Design → Implementation → Test → Review → Git commit.

Resolve requirements and design decisions before implementation. Validate and review changes before committing, within the user's authorized scope. Do not implement the entire application in one step.
