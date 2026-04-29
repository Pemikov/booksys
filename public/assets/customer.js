let currentView = 'month';
let currentDate = new Date();
let organization = null;
let businessHours = [];
let services = [];
let staff = [];
let monthlyStats = {};

async function init() {
    await loadOrganization();
    await loadBusinessHours();
    await loadServices();
    await loadStaff();
    await loadMonthlyStats();
    renderCalendar();
}

async function loadOrganization() {
    const slug = window.location.pathname.split('/').pop() || 'demo-clinic';
    const res = await fetch(`/api/calendar/organization-by-slug/${slug}`);
    const data = await res.json();
    if (data.success) {
        organization = data.organization;
        document.getElementById('orgName').innerText = organization.name;
        if (organization.primary_color) document.documentElement.style.setProperty('--primary-color', organization.primary_color);
        const contact = document.getElementById('orgContact');
        if (contact) contact.innerText = `${organization.address || ''} ${organization.phone || ''} ${organization.email || ''}`.trim();
    }
}

async function loadBusinessHours() {
    const res = await fetch(`/api/calendar/business-hours?orgId=${organization?.id || 1}`);
    const data = await res.json();
    businessHours = data.hours || [];
}

async function loadServices() {
    const res = await fetch(`/api/calendar/services?orgId=${organization?.id || 1}`);
    const data = await res.json();
    services = data.services || [];
    const select = document.getElementById('serviceSelect');
    if (select) select.innerHTML = '<option value="">Select a service</option>' + services.map(s => `<option value="${s.id}">${s.name} (${s.duration_minutes} min - $${s.price})</option>`).join('');
}

async function loadStaff() {
    const res = await fetch(`/api/calendar/staff?orgId=${organization?.id || 1}`);
    const data = await res.json();
    staff = data.staff || [];
    const select = document.getElementById('staffSelect');
    if (select) select.innerHTML = '<option value="">Any staff</option>' + staff.map(s => `<option value="${s.id}">${s.name} - ${s.role}</option>`).join('');
}

async function loadMonthlyStats() {
    const year = currentDate.getFullYear();
    const month = currentDate.getMonth() + 1;
    const res = await fetch(`/api/calendar/monthly-stats/${year}/${month}?orgId=${organization?.id || 1}`);
    const data = await res.json();
    if (data.success) {
        monthlyStats = {};
        data.stats.forEach(stat => { monthlyStats[stat.day_date.split('T')[0]] = stat; });
    }
    renderCalendar();
}

function renderCalendar() {
    const container = document.getElementById('calendarContainer');
    if (!container) return;
    if (currentView === 'month') renderMonth(container);
    else if (currentView === 'week') renderWeek(container);
    else renderDay(container);
    document.getElementById('currentDateDisplay').innerText = currentDate.toLocaleDateString();
}

function renderMonth(container) {
    const year = currentDate.getFullYear();
    const month = currentDate.getMonth();
    const firstDay = new Date(year, month, 1);
    const lastDay = new Date(year, month + 1, 0);
    const startWeekday = firstDay.getDay();
    const daysInMonth = lastDay.getDate();
    const todayStr = new Date().toISOString().split('T')[0];
    let html = '<div class="month-grid">';
    ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].forEach(d => html += `<div class="month-day-header">${d}</div>`);
    for (let i = 0; i < startWeekday; i++) html += '<div class="month-day disabled"></div>';
    for (let d = 1; d <= daysInMonth; d++) {
        const date = new Date(year, month, d);
        const dateStr = date.toISOString().split('T')[0];
        const dow = date.getDay();
        const bh = businessHours.find(h => h.day_of_week === dow);
        const isOpen = bh?.is_open === true;
        const stats = monthlyStats[dateStr] || { total_slots: 0, booked_slots: 0, free_slots: 0 };
        const free = stats.free_slots || 0;
        const booked = stats.booked_slots || 0;
        const disabled = !isOpen || (stats.total_slots > 0 && free === 0);
        html += `<div class="month-day ${dateStr === todayStr ? 'today' : ''} ${disabled ? 'disabled' : ''}"
                     onclick="${!disabled ? `selectDate('${dateStr}')` : ''}">
                    <div class="day-number">${d}</div>
                    <div class="day-stats">
                        ${isOpen ? `<span class="stats-free">${free} free</span> / <span class="stats-booked">${booked} booked</span>` : '<span class="stats-booked">Closed</span>'}
                    </div>
                </div>`;
    }
    html += '</div>';
    container.innerHTML = html;
}

async function renderWeek(container) {
    const start = new Date(currentDate);
    start.setDate(start.getDate() - start.getDay());
    const days = [];
    for (let i = 0; i < 7; i++) {
        const d = new Date(start);
        d.setDate(start.getDate() + i);
        days.push(d);
    }
    const sampleBh = businessHours.find(h => h.is_open) || { open_time: '09:00', close_time: '17:00', slot_interval: 30 };
    const slots = [];
    let cur = sampleBh.open_time;
    while (cur < sampleBh.close_time) {
        const end = addMinutes(cur, sampleBh.slot_interval);
        slots.push({ start: cur, end });
        cur = end;
    }
    let html = '<table class="weekly-table"><thead><tr>';
    days.forEach(day => html += `<th>${day.toLocaleDateString(undefined, { weekday:'short', month:'short', day:'numeric' })}</th>`);
    html += '</tr></thead><tbody>';
    for (const slot of slots) {
        html += '<tr>';
        for (const day of days) {
            const dateStr = day.toISOString().split('T')[0];
            const avail = await fetchAvailability(dateStr);
            const s = avail.find(slot => slot.slot_start === slot.start);
            const isAvail = s ? s.is_available : false;
            html += `<td class="time-slot ${isAvail ? 'available' : 'booked'}"
                         onclick="${isAvail ? `openBookingModal('${dateStr}', '${slot.start}', '${slot.end}')` : ''}">
                        ${slot.start} - ${slot.end}<br>${isAvail ? 'Available' : 'Booked'}
                     </td>`;
        }
        html += '</tr>';
    }
    html += '</tbody></table>';
    container.innerHTML = html;
}

async function renderDay(container) {
    const dateStr = currentDate.toISOString().split('T')[0];
    const dow = currentDate.getDay();
    const bh = businessHours.find(h => h.day_of_week === dow);
    if (!bh?.is_open) { container.innerHTML = '<div class="spinner">Closed</div>'; return; }
    const slots = await fetchAvailability(currentDate);
    let html = '<table class="weekly-table"><thead><tr><th>Time</th><th>Status</th><th>Staff</th><th>Action</th></tr></thead><tbody>';
    slots.forEach(slot => {
        html += `<tr class="time-slot ${slot.is_available ? 'available' : 'booked'}">
            <td>${slot.slot_start} - ${slot.slot_end}</td>
            <td>${slot.is_available ? '✅ Available' : '❌ Booked'}</td>
            <td>${slot.staff_name || 'Any'}</td>
            <td>${slot.is_available ? `<button onclick="openBookingModal('${dateStr}','${slot.slot_start}','${slot.slot_end}')">Book</button>` : 'Not available'}</td>
        </tr>`;
    });
    html += '</tbody></table>';
    container.innerHTML = html;
}

async function fetchAvailability(date) {
    const dateStr = date.toISOString ? date.toISOString().split('T')[0] : date;
    const res = await fetch(`/api/calendar/availability/${dateStr}?orgId=${organization?.id || 1}`);
    const data = await res.json();
    return data.slots || [];
}

function addMinutes(time, minutes) {
    const [h,m] = time.split(':');
    const d = new Date(); d.setHours(parseInt(h), parseInt(m));
    d.setMinutes(d.getMinutes() + minutes);
    return d.toTimeString().slice(0,5);
}

function selectDate(dateStr) {
    currentDate = new Date(dateStr);
    currentView = 'day';
    renderCalendar();
    document.querySelectorAll('.view-btn').forEach(btn => btn.classList.remove('active'));
    document.querySelector('.view-btn[data-view="day"]')?.classList.add('active');
}

function changeView(view) {
    currentView = view;
    if (view === 'month') loadMonthlyStats().then(() => renderCalendar());
    else renderCalendar();
}

function changeDate(delta) {
    if (currentView === 'month') {
        currentDate.setMonth(currentDate.getMonth() + delta);
        loadMonthlyStats();
    } else if (currentView === 'week') {
        currentDate.setDate(currentDate.getDate() + delta*7);
        renderCalendar();
    } else {
        currentDate.setDate(currentDate.getDate() + delta);
        renderCalendar();
    }
    document.getElementById('currentDateDisplay').innerText = currentDate.toLocaleDateString();
}

function openBookingModal(date, start, end) {
    window.selectedBooking = { date, start, end };
    document.getElementById('selectedSlot').innerHTML = `<strong>Date:</strong> ${date}<br><strong>Time:</strong> ${start} - ${end}`;
    document.getElementById('bookingModal').style.display = 'flex';
}

async function confirmBooking() {
    const name = document.getElementById('customerName').value;
    const email = document.getElementById('customerEmail').value;
    const phone = document.getElementById('customerPhone').value;
    const serviceId = document.getElementById('serviceSelect').value;
    const staffId = document.getElementById('staffSelect').value;
    if (!name || !email) { showToast('Name and email required'); return; }
    const booking = {
        organization_id: organization?.id || 1,
        customer_name: name,
        customer_email: email,
        customer_phone: phone,
        booking_date: window.selectedBooking.date,
        start_time: window.selectedBooking.start,
        end_time: window.selectedBooking.end,
        service_id: serviceId || null,
        staff_id: staffId || null
    };
    const res = await fetch('/api/calendar/bookings', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(booking) });
    const data = await res.json();
    if (data.success) { showToast('Booking confirmed!', 'success'); closeModal(); loadMonthlyStats(); renderCalendar(); }
    else showToast(data.error || 'Failed', 'error');
}

function closeModal() {
    document.getElementById('bookingModal').style.display = 'none';
    document.getElementById('customerName').value = '';
    document.getElementById('customerEmail').value = '';
    document.getElementById('customerPhone').value = '';
}

function showToast(msg, type='error') {
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerText = msg;
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 3000);
}

// Event listeners
document.querySelectorAll('.view-btn').forEach(btn => btn.addEventListener('click', () => changeView(btn.dataset.view)));
document.querySelectorAll('.nav-arrow').forEach((btn, idx) => btn.addEventListener('click', () => changeDate(idx === 0 ? -1 : 1)));
document.getElementById('confirmBooking')?.addEventListener('click', confirmBooking);
document.getElementById('closeModal')?.addEventListener('click', closeModal);

init();