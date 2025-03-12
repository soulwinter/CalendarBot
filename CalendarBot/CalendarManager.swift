import EventKit
import SwiftUI

class CalendarManager: ObservableObject {
    let eventStore = EKEventStore()
    @Published var calendars: [EKCalendar] = []
    @Published var events: [EKEvent] = []
    @Published var reminders: [EKReminder] = []
    
    init() {
        requestAccess()
    }
    
    func requestAccess() {
        eventStore.requestFullAccessToEvents { granted, error in
            if granted {
                DispatchQueue.main.async {
                    self.loadCalendars()
                }
            }
        }
        
        eventStore.requestFullAccessToReminders { granted, error in
            if granted {
                DispatchQueue.main.async {
                    self.loadReminders(for: Date())
                }
            }
        }
    }
    
    func loadCalendars() {
        let calendars = eventStore.calendars(for: .event)
        DispatchQueue.main.async {
            self.calendars = calendars
        }
    }
    
    func loadReminders(for date: Date) {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        var components = DateComponents()
        components.day = 1
        _ = calendar.date(byAdding: components, to: startDate)!
        
        let predicate = eventStore.predicateForReminders(in: nil)
        
        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            guard let reminders = reminders else { return }
            
            // 过滤出当天的提醒事项
            let filteredReminders = reminders.filter { reminder in
                if let dueDate = reminder.dueDateComponents?.date {
                    return calendar.isDate(dueDate, inSameDayAs: date)
                }
                return false
            }.sorted { reminder1, reminder2 in
                guard let date1 = reminder1.dueDateComponents?.date,
                      let date2 = reminder2.dueDateComponents?.date else {
                    return false
                }
                return date1 < date2
            }
            
            DispatchQueue.main.async {
                self?.reminders = filteredReminders
            }
        }
    }
    
    func loadEvents(for date: Date) {
        let startDate = Calendar.current.startOfDay(for: date)
        var components = DateComponents()
        components.day = 1
        let endDate = Calendar.current.date(byAdding: components, to: startDate)!
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        
        DispatchQueue.main.async {
            self.events = events.sorted { $0.startDate < $1.startDate }
        }
        
        // 同时加载提醒事项
        loadReminders(for: date)
    }
    
    func createCalendar(withName name: String) {
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = name
        calendar.source = eventStore.defaultCalendarForNewEvents?.source
        
        do {
            try eventStore.saveCalendar(calendar, commit: true)
            loadCalendars()
        } catch {
            print("Error creating calendar: \(error)")
        }
    }
    
    func deleteCalendar(_ calendar: EKCalendar) {
        do {
            try eventStore.removeCalendar(calendar, commit: true)
            loadCalendars()
        } catch {
            print("Error deleting calendar: \(error)")
        }
    }
    
    func createEvent(title: String, startDate: Date, endDate: Date, calendar: EKCalendar) -> Bool {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar
        
        do {
            try eventStore.save(event, span: .thisEvent)
            loadEvents(for: startDate)
            return true
        } catch {
            print("Error creating event: \(error)")
            return false
        }
    }
    
    func deleteEvent(_ event: EKEvent) -> Bool {
        do {
            try eventStore.remove(event, span: .thisEvent)
            loadEvents(for: event.startDate)
            return true
        } catch {
            print("Error deleting event: \(error)")
            return false
        }
    }
    
    func calendarColor(for calendar: EKCalendar) -> Color {
        Color(UIColor(cgColor: calendar.cgColor))
    }
    
    func loadEventsForRange(from startDate: Date, to endDate: Date) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        return events.sorted { $0.startDate < $1.startDate }
    }
    
    func formatEventsToText(events: [EKEvent]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy HH:mm"
        
        var text = "Event List:\n\n"
        
        if events.isEmpty {
            text += "No events in the selected time range.\n"
            return text
        }
        
        let groupedEvents = Dictionary(grouping: events) { event in
            Calendar.current.startOfDay(for: event.startDate)
        }
        
        let sortedDays = groupedEvents.keys.sorted()
        
        for day in sortedDays {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE, MMM d, yyyy"
            text += "=== \(dayFormatter.string(from: day)) ===\n"
            
            if let dayEvents = groupedEvents[day]?.sorted(by: { $0.startDate < $1.startDate }) {
                if dayEvents.isEmpty {
                    text += "No events today\n"
                } else {
                    for event in dayEvents {
                        text += "• [\(event.calendar.title ?? "Default Calendar")] \(event.title)\n"
                        text += "  Time: \(dateFormatter.string(from: event.startDate)) - \(dateFormatter.string(from: event.endDate))\n"
                    }
                }
            }
            text += "\n"
        }
        
        return text
    }
    
    func loadRemindersForRange(from startDate: Date, to endDate: Date, completion: @escaping ([EKReminder]) -> Void) {
        let predicate = eventStore.predicateForReminders(in: nil)
        
        eventStore.fetchReminders(matching: predicate) { reminders in
            guard let reminders = reminders else {
                completion([])
                return
            }
            
            let calendar = Calendar.current
            let filteredReminders = reminders.filter { reminder in
                if let dueDate = reminder.dueDateComponents?.date {
                    return dueDate >= startDate && dueDate < endDate
                }
                return false
            }.sorted { reminder1, reminder2 in
                guard let date1 = reminder1.dueDateComponents?.date,
                      let date2 = reminder2.dueDateComponents?.date else {
                    return false
                }
                return date1 < date2
            }
            
            completion(filteredReminders)
        }
    }
    
    func formatRemindersToText(reminders: [EKReminder]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy HH:mm"
        
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "MMM d, yyyy"
        
        var text = "Reminder List:\n\n"
        
        if reminders.isEmpty {
            text += "No reminders in the selected time range.\n"
            return text
        }
        
        let groupedReminders = Dictionary(grouping: reminders) { reminder in
            Calendar.current.startOfDay(for: reminder.dueDateComponents?.date ?? Date())
        }
        
        let sortedDays = groupedReminders.keys.sorted()
        
        for day in sortedDays {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE, MMM d, yyyy"
            text += "=== \(dayFormatter.string(from: day)) ===\n"
            
            if let dayReminders = groupedReminders[day]?.sorted(by: { 
                ($0.dueDateComponents?.date ?? Date()) < ($1.dueDateComponents?.date ?? Date())
            }) {
                for reminder in dayReminders {
                    text += "• [\(reminder.calendar.title ?? "Default Reminder")] \(reminder.title)\n"
                    if let dueDate = reminder.dueDateComponents?.date {
                        let hasTime = reminder.dueDateComponents?.hour != nil
                        text += "  Due: \(hasTime ? dateFormatter.string(from: dueDate) : dateOnlyFormatter.string(from: dueDate))\n"
                    }
                    text += "  Status: \(reminder.isCompleted ? "Completed" : "Pending")\n"
                }
            }
            text += "\n"
        }
        
        return text
    }
    
    func formatEventsAndRemindersToText(from startDate: Date, to endDate: Date, completion: @escaping (String) -> Void) {
        let events = loadEventsForRange(from: startDate, to: endDate)
        loadRemindersForRange(from: startDate, to: endDate) { reminders in
            let eventsText = self.formatEventsToText(events: events)
            let remindersText = self.formatRemindersToText(reminders: reminders)
            let combinedText = "\(eventsText)\n\(remindersText)"
            completion(combinedText)
        }
    }
    
    func createDifyEvents(_ difyEvents: [DifyEvent]) -> Bool {
        var success = true
        let formatter = ISO8601DateFormatter.difyFormatter
        
        for difyEvent in difyEvents {
            guard let startDate = formatter.date(from: difyEvent.dtstart),
                  let endDate = formatter.date(from: difyEvent.dtend) else {
                print("Error parsing dates for event: \(difyEvent.summary)")
                print("dtstart: \(difyEvent.dtstart)")
                print("dtend: \(difyEvent.dtend)")
                success = false
                continue
            }
            
            let event = EKEvent(eventStore: eventStore)
            event.title = difyEvent.summary
            event.startDate = startDate
            event.endDate = endDate
            event.location = difyEvent.location
            event.notes = difyEvent.description
            event.calendar = eventStore.defaultCalendarForNewEvents
            
            do {
                try eventStore.save(event, span: .thisEvent)
                print("✅ Successfully created event: \(difyEvent.summary)")
            } catch {
                print("❌ Error creating Dify event: \(error)")
                success = false
            }
        }
        
        if success {
            loadEvents(for: Date())
        }
        
        return success
    }
} 
