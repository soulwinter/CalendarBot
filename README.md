# CalendarBot

CalendarBot is an iOS application that helps you manage your calendar events and reminders more efficiently. It integrates with Apple's EventKit framework and uses AI to help schedule and organize your events.

## Features

- View, create, and delete calendar events
- Manage reminders with due dates
- Export events and reminders in formatted text
- AI-powered scheduling assistance using Dify API
- Support for multiple calendars
- Beautiful and intuitive user interface

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.0+

## Installation

1. Clone the repository
```bash
git clone https://github.com/yourusername/CalendarBot.git
```

2. Open `CalendarBot.xcodeproj` in Xcode

3. Create a `Config.swift` file in the project and add your Dify API key:
```swift
struct Config {
    static let difyAPIKey = "YOUR_API_KEY_HERE"
}
```

4. Build and run the project

## Configuration

### Calendar Permissions
The app requires calendar and reminder permissions to function. Make sure to add the following keys to your `Info.plist`:

- `NSCalendarsFullAccessUsageDescription`
- `NSRemindersFullAccessUsageDescription`

### API Configuration
To use the AI scheduling features:
1. Get an API key from [Dify](https://dify.ai)
2. Add it to `Config.swift`

## Usage

### Managing Events
- View events in the calendar view
- Create new events using the + button
- Delete events by swiping left
- Export events using the share button

### AI Scheduling
- Select a date range to analyze
- The app will suggest optimal scheduling based on your existing events and reminders
- Review and approve the suggested schedule

## Architecture

The app follows a clean architecture pattern and uses:
- SwiftUI for the user interface
- EventKit for calendar management
- Combine for reactive programming
- MVVM pattern for view management

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details

## Acknowledgments

- [EventKit](https://developer.apple.com/documentation/eventkit)
- [Dify AI](https://dify.ai)
- All contributors to this project 