// admin-calendar.js
let calendar = null;
let currentOrgId = null;
let adminToken = null;
let currentServiceDuration = 30; // default

// Helper to get all possible slots for a date range (uses your existing availability API)
async function getAllSlotsInRange(start, end, orgId) {
    const events = [];
    const days = [];
    let current = new Date(start);
    while (current <= end) {
        days.push(new Date(current));
        current.setDate(current.getDate() + 1);
    }
    for (const day of days) {
        const dateStr = day.toISOString().split('T')[0];
        const res = await fetch(`/api/admin/availability/${dateStr}`, {
            headers: { 'Authorization': adminToken }
        });
        const data = await res.json();
        const slots = data.slots || [];
        for (const slot of slots) {
            const startDateTime = new Date(`${dateStr}T${slot.slot_start}`);
            const endDateTime = new Date(`${dateStr}T${slot.slot_end}`);
            if (slot.is_available) {
                events.push({
                    id: `avail_${dateStr}_${slot.slot_start}`,
                    title: 'Available',
                    start: startDateTime,
                    end: endDateTime,
                    extendedProps: { type: 'available', slotData: slot },
                    color: '#28a745',
                    textColor: 'white',
                    classNames: ['fc-available-slot']
                });
            } else {
                events.push({
                    id: `booked_${slot.booking_id}`,
                    title: `Booked: ${slot.customer_name || 'Customer'}`,
                    start: startDateTime,
                    end: endDateTime,
                    extendedProps: { type: 'booked', bookingId: slot.booking_id, slotData: slot },
                    color: '#dc3545',
                    textColor: 'white',
                    classNames: ['fc-booked-slot']
                });
            }
        }
    }
    return events;
}

// Fetch real bookings (optional – we already get them from availability, but for safety we can merge)
async function fetchBookingsEvents(start, end, orgId) {
    // Not strictly needed because availability already returns all slots (available + booked)
    // Kept for future extension
    return [];
}

// Load services for the dropdown
async function loadServiceSelector(orgId) {
    const res = await fetch('/api/admin/services', { headers: { 'Authorization': adminToken } });
    const data = await res.json();
    const services = data.services || [];
    const selector = document.getElementById('serviceSlotSelector');
    if (!selector) return;
    selector.innerHTML = '<option value="">-- Select service to set slot duration --</option>' +
        services.map(s => `<option value="${s.duration_minutes}">${s.name} (${s.duration_minutes} min)</option>`).join('');
    selector.addEventListener('change', (e) => {
        const newDuration = parseInt(e.target.value, 10);
        if (!isNaN(newDuration) && calendar) {
            // Update slot duration and snap duration
            const slotDur = `00:${newDuration}:00`;
            calendar.setOption('slotDuration', slotDur);
            calendar.setOption('snapDuration', slotDur);
            calendar.refetchEvents();
            currentServiceDuration = newDuration;
        }
    });
}

// Main init function
async function initFullCalendar(container, orgId, token) {
    adminToken = token;
    currentOrgId = orgId;
    // Event source: called whenever the date range changes
    const eventSource = {
        events: async (fetchInfo, successCallback, failureCallback) => {
            const start = fetchInfo.start;
            const end = fetchInfo.end;
            try {
                const slots = await getAllSlotsInRange(start, end, orgId);
                successCallback(slots);
            } catch (err) {
                console.error(err);
                failureCallback(err);
            }
        }
    };
    calendar = new FullCalendar.Calendar(container, {
        initialView: 'dayGridMonth',
        headerToolbar: {
            left: 'prev,next today',
            center: 'title',
            right: 'dayGridMonth,timeGridWeek,timeGridDay'
        },
        events: eventSource,
        eventClick: (info) => {
            const props = info.event.extendedProps;
            if (props.type === 'available') {
                const slot = props.slotData;
                const dateStr = info.event.start.toISOString().split('T')[0];
                // Use your existing global modal function
                if (typeof openAdminBookingModal === 'function') {
                    openAdminBookingModal(dateStr, slot.slot_start, slot.slot_end);
                } else {
                    alert('Booking modal not available');
                }
            } else if (props.type === 'booked') {
                const bookingId = props.bookingId;
                if (confirm('Cancel this booking?')) {
                    if (typeof adminCancelBooking === 'function') {
                        adminCancelBooking(bookingId);
                    } else {
                        alert('Cancel function not available');
                    }
                }
            }
        },
        eventDrop: async (info) => {
            const event = info.event;
            const bookingId = event.extendedProps.bookingId;
            if (!bookingId) return; // only booked events should be draggable
            const newStart = event.start;
            const newEnd = event.end;
            const newDate = newStart.toISOString().split('T')[0];
            const newStartTime = newStart.toTimeString().slice(0,8);
            const newEndTime = newEnd.toTimeString().slice(0,8);
            const res = await fetch(`/api/admin/bookings/${bookingId}/reschedule`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json', 'Authorization': adminToken },
                body: JSON.stringify({ booking_date: newDate, start_time: newStartTime, end_time: newEndTime })
            });
            if (res.ok) {
                if (typeof showToast === 'function') showToast('Booking moved', 'success');
                calendar.refetchEvents();
            } else {
                if (typeof showToast === 'function') showToast('Move failed', 'error');
                calendar.refetchEvents(); // revert
            }
        },
        eventResize: async (info) => {
            const event = info.event;
            const bookingId = event.extendedProps.bookingId;
            if (!bookingId) return;
            const newStart = event.start;
            const newEnd = event.end;
            const newStartTime = newStart.toTimeString().slice(0,8);
            const newEndTime = newEnd.toTimeString().slice(0,8);
            const res = await fetch(`/api/admin/bookings/${bookingId}/resize`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json', 'Authorization': adminToken },
                body: JSON.stringify({ start_time: newStartTime, end_time: newEndTime })
            });
            if (res.ok) {
                if (typeof showToast === 'function') showToast('Booking resized', 'success');
                calendar.refetchEvents();
            } else {
                if (typeof showToast === 'function') showToast('Resize failed', 'error');
                calendar.refetchEvents();
            }
        },
        editable: true,
        droppable: false,
        slotDuration: `00:${currentServiceDuration}:00`,
        snapDuration: `00:${currentServiceDuration}:00`,
        slotLabelInterval: '01:00',
        allDaySlot: false,
        nowIndicator: true,
        businessHours: false,
        height: 'auto'
    });
    calendar.render();

    // Load service selector dropdown after calendar is rendered
    await loadServiceSelector(orgId);
}

// Expose a destroy function
window.destroyCalendar = () => {
    if (calendar) {
        calendar.destroy();
        calendar = null;
    }
};