# Shift App:
Organizing and AI assisting for stewards / people with changing schedules or hourly rates / students that also work. Basically people with fluctuating schedules.

Accent color: use Apple's blue color.

The app has four views with three panels each:

1. Home
2. Assistant
3. Income
4. Settings

The top panel is a top bar showing the title of the view (centered), for views 1 & 3 also show the month actively looking at the moment, with a left and right arrow to go back and forth. Then the middle part has the main content of the view. Bottom part has a navigation bar to the other views.

1. The home page is a monthly calendar view with every event in which he is working is registered. The view is fixed (can't zoom in/out). The user can tap a day to list all events on that day, showing a list of events with basic information (Title, Start-End time). He can then tap an event to see detailed information (Title, Start-End time, Address, Hourly Rate, Additional information, such as special needs for this specific event). When the worker has more events/entries in a day in such way that not all of them fit inside of the day's box in the monthly view, it will show as many as they fit and then a '+ (n - shown events) More' underneath (when tap it will be prompted a scrollable page with the list of ). For this specific view, the top bar will also have a + circled button to the right in which you are able to manually create a new entry. I will pop up a page in which you can out all details of the event to add it.

2. This is a regular chat page in which you can chat with an AI assistant that will help you out. You can upload files (csv, xlsx, xls, pdf, png, jpeg, jpg) to provide to the AI, with your shifts, or assignments, for it to add them all to the calendar, so you don't have to manually entry everything. Of course, you can text all of it too, remove, add, change, fix, etc. Really helpful if for example you want to add something periodically, let's say 'add a shift every Thursday from 14:30-19:00 from now until September, skip every other week and don't add it on national holidays'. Here there are no months so on the top bar it will not show any month nor arrows, only panel title 'Assistant'.

3. On the Income page the user is able to see the month's paycheck, underneath listing all events done on that month. Here we have the months and arrows back on the top bar.

4. Here the user can change every aspect of the app. Colors, presets (yes you can create a preset so that its easier to add in the future. I.e: 'Name: Partido Real Madrid, Hourly Rate or Fixed Rate? Lenght and Rate or Enter Fixed Rate' and so when adding a new event you can select this preset), etc, the AI Assistant will also be able to create, delete, change these items.


When the user first starts the app, he will be prompted the main use he'll give. Work, school, and regular calendar, regular calendar and work is always implied but the user can select school too. This means The user will access a 'new section':
When clicking add new event, it will say 'Title:' and then like a slider with the options he has 'Work - School (if enabled) - Calendar'.
Each of those has a different continue of the page, work has hourly rate, time etc, school have another slider to select either Exam - Assignment - Other, and then time, if exam it will just say exam and if it is one of the other they will have a custom title.
All the options must be REQUIRED but one -> Notes. The notes field is optional and capped at **250 characters**. Conditional fields are required only when they apply: a work event must have either an hourly or fixed rate; a school event must have a school kind and subject; a regular calendar event has no compensation fields.
The AI Agent must know if school is enabled in order to add correctly the entries. It can suggest to enable it if the user asks to add something that would be ideal to add in that section.

In settings it can be enabled. When enabled School, it will show the section subjects, in which you can add/remove your subjects (when adding a school event there will be a quick add subject for UX) when removing a subject, it will delete all its events, so it will prompt a 'Are you sure you want to delete? This will delete all linked events'.

For the AI it will have a section in Settings. Tell me how can I use my Claude code subscription, I don't want APIs, I want the sign in option, if possible.

The app will only be able in vertical mode for iPhone, and it will be available in all iOS devices, Mac, iPhone, iPad. Also everything should be linked between devices, so the user can see changes from its phone on the iPad for example. For Mac and iPad on horizontal, the Panel will be Top bar same, Bottom bar will be at the left, and the main view on the right panel, of course, the left panel been much smaller, fixed to the size of the largest name on the nav bar, the icon of it will be on the left.

I want to use the svgs given by apple everywhere, it whould look clean, minimalist and simple. Settings: Both light and dark mode, implement also a language changer (add main languages used in normal apps).

**Hard requirement:** no request can be forwarded without a successful atomic reservation. A simple “sum prior usage, then call the model” check is not sufficient because concurrent requests can both pass it.
    
I have also added a excel file with the information for the rates there for easier readability.


ASK ALL QUESTIONS BEFORE DEVELOPING THE APP. ALL KINDS OF QUESTIONS. ASUME NOTHING. ASK SUGGESTIONS IF YOU HAVE ANY. FIRST WE MODEL THEN WE DEVELOP.

Stack:
    Swift
    SwiftUI
    SwiftData
