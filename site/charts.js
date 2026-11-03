(function () {
  const data = window.SITE_DATA;
  if (!data || !data.dashboard) return;

  const dash = data.dashboard;
  const NAVY = "#1B2A41";
  const POWDER = "rgba(167, 199, 231, 0.85)";

  Chart.defaults.font.family = '"Avenir Next", "Segoe UI", "Helvetica Neue", sans-serif';
  Chart.defaults.color = NAVY;
  Chart.defaults.font.size = 13;

  const goal = dash.goals[0];
  document.getElementById("asof").textContent =
    "Day " + goal.daysElapsed + " of " + goal.daysInQuarter + " in the quarter.";

  const tiles = document.getElementById("goal-tiles");
  dash.goals.forEach(function (item) {
    const fill = Math.max(0, Math.min(100, item.progress * 100));
    const article = document.createElement("article");
    article.className = "goal " + item.status;
    const pace = item.kind === "pace" && item.pace != null
      ? '<i class="pace" style="left:' + Math.max(0, Math.min(100, item.pace * 100)) + '%"></i>'
      : "";
    article.innerHTML =
      '<div class="goal-top"><h3>' + item.label + '</h3><span class="pill">' + item.statusLabel + "</span></div>" +
      '<p class="goal-value">' + item.currentLabel + "</p>" +
      '<p class="goal-target">Goal ' + item.targetLabel + "</p>" +
      '<div class="bar" aria-hidden="true"><span style="width:' + fill + '%"></span>' + pace + "</div>" +
      '<p class="detail">' + item.detail + "</p>";
    tiles.appendChild(article);
  });

  const actions = document.getElementById("action-list");
  dash.actions.forEach(function (item) {
    const li = document.createElement("li");
    const link = document.createElement("a");
    link.href = "#" + item.sectionId;
    const title = document.createElement("strong");
    title.textContent = item.title + ". ";
    link.appendChild(title);
    link.appendChild(document.createTextNode(item.sentence));
    li.appendChild(link);
    actions.appendChild(li);
  });

  function money(value) {
    const abs = Math.abs(value);
    if (abs >= 1000000) {
      const millions = abs / 1000000;
      const digits = millions >= 10 || Math.abs(millions - Math.round(millions)) < 0.05 ? 0 : 1;
      return "$" + millions.toFixed(digits) + "M";
    }
    return "$" + Math.round(abs / 1000) + "k";
  }

  const note = dash.months.map(function (month) { return month.note; }).filter(Boolean)[0];
  document.getElementById("cap-bookings").textContent =
    "Bars are closed-won ARR. The line is one third of the quarter goal." +
    (note ? " " + note : "");

  Chart.defaults.animation = false;

  new Chart(document.getElementById("bookings"), {
    type: "bar",
    data: {
      labels: dash.months.map(function (month) { return month.label; }),
      datasets: [
        {
          type: "bar",
          label: "Bookings",
          data: dash.months.map(function (month) { return month.bookings; }),
          backgroundColor: POWDER,
          borderColor: NAVY,
          borderWidth: 1,
          borderRadius: 6,
          order: 2,
        },
        {
          type: "line",
          label: "Monthly goal",
          data: dash.months.map(function (month) { return month.goal; }),
          borderColor: NAVY,
          borderDash: [5, 4],
          pointRadius: 0,
          borderWidth: 2,
          order: 1,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { position: "bottom", labels: { boxWidth: 14 } },
        tooltip: {
          callbacks: {
            label: function (ctx) { return ctx.dataset.label + " " + money(ctx.parsed.y); },
          },
        },
      },
      scales: {
        y: {
          beginAtZero: true,
          ticks: { callback: function (value) { return money(value); } },
          grid: { color: "rgba(167, 199, 231, 0.45)" },
        },
        x: { grid: { display: false } },
      },
    },
  });

  const lead = dash.funnel[0].reached || 1;
  const funnel = document.getElementById("funnel");
  dash.funnel.forEach(function (stage) {
    const row = document.createElement("div");
    row.className = "funnel-row";
    const width = Math.max(8, (stage.reached / lead) * 100);
    const conv = stage.conversion == null
      ? ""
      : '<span class="conv">' + Math.round(stage.conversion * 100) + "% of the previous stage</span>";
    row.innerHTML =
      '<div class="funnel-label"><strong>' + stage.label + "</strong>" + conv + "</div>" +
      '<div class="funnel-track"><span style="width:' + width + '%">' + stage.reached + "</span></div>";
    funnel.appendChild(row);
  });

  const wins = document.getElementById("wins");
  dash.wins.forEach(function (item) {
    const card = document.createElement("article");
    card.className = "win-card";
    card.innerHTML =
      "<h3>" + item.label + "</h3>" +
      '<p class="goal-value">' + Math.round(item.rate * 100) + "%</p>" +
      '<p class="detail">' + item.won + " won of " + item.closed + " closed</p>" +
      '<div class="bar" aria-hidden="true"><span style="width:' + Math.round(item.rate * 100) + '%"></span></div>';
    wins.appendChild(card);
  });

  const channelLabels = dash.channels.map(function (item) { return item.name; });

  function horizontal(canvas, values, label, tick) {
    new Chart(canvas, {
      type: "bar",
      data: {
        labels: channelLabels,
        datasets: [{
          label: label,
          data: values,
          backgroundColor: POWDER,
          borderColor: NAVY,
          borderWidth: 1,
          borderRadius: 6,
        }],
      },
      options: {
        indexAxis: "y",
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: function (ctx) { return tick(ctx.parsed.x); },
            },
          },
        },
        scales: {
          x: {
            beginAtZero: true,
            ticks: { callback: function (value) { return tick(value); } },
            grid: { color: "rgba(167, 199, 231, 0.45)" },
          },
          y: { grid: { display: false } },
        },
      },
    });
  }

  horizontal(document.getElementById("pipeline"), dash.channels.map(function (item) { return item.pipeline; }), "Pipeline", money);
  horizontal(
    document.getElementById("cost"),
    dash.channels.map(function (item) { return item.cost; }),
    "Cost",
    function (value) { return "$" + Math.round(value).toLocaleString("en-US"); }
  );

  const health = document.getElementById("health");
  dash.accounts.forEach(function (account) {
    const row = document.createElement("article");
    row.className = "health-row " + account.healthBand + (account.renewalAtRisk ? " flagged" : "");
    row.innerHTML =
      '<div><strong>' + account.name + "</strong><span>" + account.segment + "</span></div>" +
      '<div><span class="k">Adoption</span><b>' + account.adoption + "</b></div>" +
      '<div><span class="k">Trend</span><b class="trend ' + account.trend + '">' + account.trendLabel + "</b></div>" +
      '<div><span class="k">Renewal</span><b>' + account.renewal + "</b></div>" +
      '<div class="score"><span class="k">Health</span><b>' + account.healthScore + " " + account.healthLabel + "</b></div>";
    health.appendChild(row);
  });

  const saved = dash.timeSaved;
  document.getElementById("cap-saved").textContent = saved.caption;
  new Chart(document.getElementById("saved"), {
    type: "bar",
    data: {
      labels: ["Before", "After"],
      datasets: [{
        label: "Minutes on the report",
        data: [saved.beforeMinutes, saved.afterMinutes],
        backgroundColor: [POWDER, NAVY],
        borderRadius: 8,
        barPercentage: 0.55,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: {
        y: {
          beginAtZero: true,
          title: { display: true, text: "Minutes" },
          grid: { color: "rgba(167, 199, 231, 0.45)" },
        },
        x: { grid: { display: false } },
      },
    },
  });

  const change = data.headlines.reportChange;
  const turn = data.headlines.turnaroundChange;
  const raw = data.headlines.rawTurnaround;
  const meta = data.meta;
  const low = Math.min(Math.abs(change.lo), Math.abs(change.hi));
  const high = Math.max(Math.abs(change.lo), Math.abs(change.hi));
  const one = function (value) { return Math.abs(value).toFixed(1); };
  const pct = function (value) { return (value * 100).toFixed(1); };
  document.getElementById("method-stats").textContent =
    "On " + meta.nStudies.toLocaleString("en-US") +
    " studies, time on the report moved from " + one(change.before) +
    " minutes to " + one(change.after) +
    ", about " + one(change.value) +
    " minutes faster when each modality is compared with itself and weighted by the pre-launch mix. MRI rose from " +
    pct(meta.mriBefore) + "% to " + pct(meta.mriAfter) +
    "%, so the raw turnaround went from " + one(raw.before) +
    " to " + one(raw.after) +
    ". Mix-adjusted turnaround still fell, from " + one(turn.before) +
    " to " + one(turn.after) +
    ". A 95% bootstrap interval on the report-time change runs from " +
    low.toFixed(1) + " to " + high.toFixed(1) +
    " minutes faster, with " + meta.bootstrapDraws.toLocaleString("en-US") +
    " resamples and seed " + meta.seed +
    ". It is not drawn on the chart. " + meta.partialStudies +
    " studies in the last two days are still loading and stay out.";
})();
