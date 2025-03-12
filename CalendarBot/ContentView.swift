//
//  ContentView.swift
//  CalendarBot
//
//  Created by Chubo Han on 3/12/25.
//

import SwiftUI
import EventKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var calendarManager = CalendarManager()
    @State private var selectedDate = Date()
    @State private var showingNewEventSheet = false
    @State private var selectedCalendar: EKCalendar?
    @State private var showingSettingsSheet = false
    
    // 新事件的状态
    @State private var newEventTitle = ""
    @State private var newEventStartDate = Date()
    @State private var newEventEndDate = Date().addingTimeInterval(3600)
    
    // 删除确认
    @State private var eventToDelete: EKEvent?
    @State private var showingDeleteConfirmation = false
    
    // 导出相关状态
    @State private var showingExportSheet = false
    @State private var exportStartDate = Calendar.current.startOfDay(for: Date().addingTimeInterval(24*3600))
    @State private var exportEndDate = Calendar.current.startOfDay(for: Date().addingTimeInterval(24*3600)).addingTimeInterval(24*3600)
    @State private var showingExportOptions = false
    
    // Dify API 相关状态
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingErrorAlert = false
    @State private var showingSuccessAlert = false
    
    // State properties
    @State private var selectedCalendars: Set<EKCalendar> = []
    
    private func prepareAndShowExport() {
        print("Starting export preparation...")
        let events = calendarManager.loadEventsForRange(from: exportStartDate, to: exportEndDate, calendars: Array(selectedCalendars))
        let eventsText = calendarManager.formatEventsToText(events: events)
        print("Events text prepared: \n\(eventsText)")
        
        print("Loading reminders...")
        calendarManager.loadRemindersForRange(from: exportStartDate, to: exportEndDate) { reminders in
            let remindersText = self.calendarManager.formatRemindersToText(reminders: reminders)
            print("Reminders text prepared: \n\(remindersText)")
            
            Task {
                print("Starting Dify API request...")
                isLoading = true
                do {
                    print("Sending request to Dify API...")
                    let response = try await DifyAPI.shared.submitEvents(
                        existedEvents: eventsText,
                        plans: remindersText
                    )
                    
                    await MainActor.run {
                        isLoading = false
                        print("Received Dify API response: status=\(response.status)")
                        
                        if response.status == 0 {
                            errorMessage = response.message ?? "Unknown error"
                            print("❌ API returned error: \(response.message ?? "No error message")")
                            showingErrorAlert = true
                        } else if let events = response.events {
                            print("✅ API returned \(events.count) events")
                            if calendarManager.createDifyEvents(events) {
                                print("✅ Successfully created all events")
                                calendarManager.loadEvents(for: selectedDate)
                                showingSuccessAlert = true
                            } else {
                                errorMessage = "Failed to create events"
                                print("❌ Failed to create events")
                                showingErrorAlert = true
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = error.localizedDescription
                        print("❌ API request failed: \(error)")
                        showingErrorAlert = true
                    }
                }
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    DatePicker("Select Date", selection: $selectedDate, displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                        .onChange(of: selectedDate) { _ in
                            calendarManager.loadEvents(for: selectedDate, calendars: Array(selectedCalendars))
                        }
                    
                    List {
                        Section("Today's Events") {
                            if calendarManager.events.isEmpty {
                                Text("No events today")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(calendarManager.events, id: \.eventIdentifier) { event in
                                    EventRow(event: event, calendarManager: calendarManager)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                eventToDelete = event
                                                showingDeleteConfirmation = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                        
                        Section("Today's Reminders") {
                            if calendarManager.reminders.isEmpty {
                                Text("No reminders today")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(calendarManager.reminders, id: \.calendarItemIdentifier) { reminder in
                                    ReminderRow(reminder: reminder)
                                }
                            }
                        }
                    }
                }
                
                if isLoading {
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.all)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingSettingsSheet = true
                    }) {
                        Image(systemName: "gear")
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingExportOptions = true
                    }) {
                        Image(systemName: "calendar.badge.plus")
                    }
                    .disabled(isLoading || selectedCalendars.isEmpty)
                    
                    Button(action: {
                        showingNewEventSheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingSettingsSheet) {
                NavigationView {
                    List {
                        Section("Calendar Selection") {
                            ForEach(calendarManager.calendars, id: \.calendarIdentifier) { calendar in
                                HStack {
                                    Circle()
                                        .fill(calendarManager.calendarColor(for: calendar))
                                        .frame(width: 12, height: 12)
                                    Text(calendar.title ?? "Default Calendar")
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { selectedCalendars.contains(calendar) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedCalendars.insert(calendar)
                                            } else {
                                                selectedCalendars.remove(calendar)
                                            }
                                            calendarManager.loadEvents(for: selectedDate, calendars: Array(selectedCalendars))
                                        }
                                    ))
                                }
                            }
                        }
                    }
                    .navigationTitle("Settings")
                    .navigationBarItems(trailing: Button("Done") {
                        showingSettingsSheet = false
                    })
                }
            }
            .confirmationDialog("Select Export Range", isPresented: $showingExportOptions, titleVisibility: .visible) {
                Button("Tomorrow (1 day)") {
                    exportStartDate = Calendar.current.startOfDay(for: Date().addingTimeInterval(24*3600))
                    exportEndDate = Calendar.current.startOfDay(for: Date().addingTimeInterval(48*3600))
                    prepareAndShowExport()
                }
                .disabled(isLoading)
                
                Button("Next Week") {
                    exportStartDate = Calendar.current.startOfDay(for: Date())
                    exportEndDate = Calendar.current.startOfDay(for: Date().addingTimeInterval(7*24*3600))
                    prepareAndShowExport()
                }
                .disabled(isLoading)
                
                Button("Custom Range") {
                    showingExportSheet = true
                }
                .disabled(isLoading)
                
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showingExportSheet) {
                NavigationView {
                    Form {
                        DatePicker("Start Date", selection: $exportStartDate, displayedComponents: [.date])
                        DatePicker("End Date", selection: $exportEndDate, displayedComponents: [.date])
                    }
                    .navigationTitle("Select Export Range")
                    .navigationBarItems(
                        leading: Button("Cancel") {
                            showingExportSheet = false
                        },
                        trailing: Button("Export") {
                            showingExportSheet = false
                            prepareAndShowExport()
                        }
                        .disabled(isLoading)
                    )
                }
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .alert("Success", isPresented: $showingSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Successfully created new events")
            }
            .sheet(isPresented: $showingNewEventSheet) {
                NavigationView {
                    Form {
                        TextField("Event Title", text: $newEventTitle)
                        
                        DatePicker("Start Time", selection: $newEventStartDate)
                        DatePicker("End Time", selection: $newEventEndDate)
                        
                        Picker("Select Calendar", selection: $selectedCalendar) {
                            ForEach(calendarManager.calendars, id: \.calendarIdentifier) { calendar in
                                HStack {
                                    Circle()
                                        .fill(calendarManager.calendarColor(for: calendar))
                                        .frame(width: 12, height: 12)
                                    Text(calendar.title ?? "Default Calendar")
                                }
                                .tag(Optional(calendar))
                            }
                        }
                    }
                    .navigationTitle("New Event")
                    .navigationBarItems(
                        leading: Button("Cancel") {
                            showingNewEventSheet = false
                        },
                        trailing: Button("Add") {
                            if let calendar = selectedCalendar, !newEventTitle.isEmpty {
                                if calendarManager.createEvent(
                                    title: newEventTitle,
                                    startDate: newEventStartDate,
                                    endDate: newEventEndDate,
                                    calendar: calendar
                                ) {
                                    newEventTitle = ""
                                    showingNewEventSheet = false
                                }
                            }
                        }
                        .disabled(selectedCalendar == nil || newEventTitle.isEmpty)
                    )
                }
            }
            .alert("Confirm Delete", isPresented: $showingDeleteConfirmation, presenting: eventToDelete) { event in
                Button("Delete", role: .destructive) {
                    if calendarManager.deleteEvent(event) {
                        eventToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    eventToDelete = nil
                }
            } message: { event in
                Text("Are you sure you want to delete event \(event.title)?")
            }
        }
        .onAppear {
            calendarManager.loadEvents(for: selectedDate)
        }
    }
}

struct EventRow: View {
    let event: EKEvent
    let calendarManager: CalendarManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(calendarManager.calendarColor(for: event.calendar))
                    .frame(width: 12, height: 12)
                Text(event.calendar.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(event.title)
                .font(.headline)
            Text("\(event.startDate, style: .time) - \(event.endDate, style: .time)")
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

struct ReminderRow: View {
    let reminder: EKReminder
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(reminder.isCompleted ? .green : .gray)
                Text(reminder.calendar.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(reminder.title)
                .font(.headline)
            if let dueDate = reminder.dueDateComponents?.date {
                let hasTime = reminder.dueDateComponents?.hour != nil
                Text("截止日期：\(dueDate, style: hasTime ? .time : .date)")
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let textFile = text.data(using: .utf8)!
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("events.txt")
        try? textFile.write(to: tempURL)
        
        let activityViewController = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
        return activityViewController
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
