(function () {
  const data = window.SITE_DATA;
  if (!data) return;

  const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  const MODS = ["CT", "MRI", "XR", "US"];
  const NAVY = "#1B2A41";
  const POWDER = "rgba(167, 199, 231, 0.62)";
  const GREEN = "#1F6B4A";
  const ROSE = "#8C3D52";
  const GREY = "#C5CED8";
  const charts = {};

  Chart.defaults.font.family = '"Avenir Next", "Segoe UI", "Helvetica Neue", sans-serif';
  Chart.defaults.color = NAVY;
  Chart.defaults.font.size = 12;

  const launchPlugin = {
    id: "launchLine",
    afterDraw(chart, _args, opts) {
      const labels = chart.data.labels || [];
      const idx = labels.indexOf(opts.week);
      if (idx < 0) return;
      const x = chart.scales.x.getPixelForTick(idx);
      const area = chart.chartArea;
      const ctx = chart.ctx;
      ctx.save();
      ctx.strokeStyle = NAVY;
      ctx.setLineDash([4, 4]);
      ctx.lineWidth = 1.25;
      ctx.beginPath();
      ctx.moveTo(x, area.top);
      ctx.lineTo(x, area.bottom);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.font = "12px Avenir Next, Segoe UI, sans-serif";
      ctx.fillStyle = NAVY;
      ctx.textAlign = x > area.left + (area.right - area.left) * 0.72 ? "right" : "left";
      ctx.fillText("Launch", ctx.textAlign === "right" ? x - 6 : x + 6, area.top + 14);
      ctx.restore();
    },
  };

  const sitePlugin = {
    id: "siteWhiskers",
    afterDatasetsDraw(chart) {
      const meta = chart.getDatasetMeta(0);
      const ds = chart.data.datasets[0];
      const ctx = chart.ctx;
      const xScale = chart.scales.x;
      ctx.save();
      ctx.strokeStyle = NAVY;
      ctx.fillStyle = NAVY;
      ctx.lineWidth = 1.4;
      meta.data.forEach((bar, i) => {
        if (ds.lo[i] == null || ds.hi[i] == null) return;
        const x1 = xScale.getPixelForValue(ds.lo[i]);
        const x2 = xScale.getPixelForValue(ds.hi[i]);
        const y = bar.y;
        ctx.beginPath();
        ctx.moveTo(x1, y);
        ctx.lineTo(x2, y);
        ctx.moveTo(x1, y - 5);
        ctx.lineTo(x1, y + 5);
        ctx.moveTo(x2, y - 5);
        ctx.lineTo(x2, y + 5);
        ctx.stroke();
      });
      if (ds.group != null) {
        const gx = xScale.getPixelForValue(ds.group);
        const area = chart.chartArea;
        ctx.setLineDash([5, 4]);
        ctx.strokeStyle = GREEN;
        ctx.beginPath();
        ctx.moveTo(gx, area.top);
        ctx.lineTo(gx, area.bottom);
        ctx.stroke();
        ctx.setLineDash([]);
        ctx.font = "11px Avenir Next, Segoe UI, sans-serif";
        const label = "Group";
        const tw = ctx.measureText(label).width;
        const tx = Math.min(gx + 6, area.right - tw - 4);
        const ty = area.top + 14;
        ctx.fillStyle = "rgba(255,255,255,0.92)";
        ctx.fillRect(tx - 3, ty - 11, tw + 6, 15);
        ctx.fillStyle = GREEN;
        ctx.textAlign = "left";
        ctx.fillText(label, tx, ty);
      }
      ctx.restore();
    },
  };

  const aiLabels = {
    id: "aiLabels",
    afterDatasetsDraw(chart) {
      const ctx = chart.ctx;
      chart.data.datasets.forEach((ds, di) => {
        const meta = chart.getDatasetMeta(di);
        meta.data.forEach((bar, i) => {
          const value = ds.data[i];
          if (value < 12) return;
          const center = bar.getCenterPoint();
          ctx.save();
          ctx.fillStyle = di === 0 ? "#ffffff" : NAVY;
          ctx.font = "12px Avenir Next, Segoe UI, sans-serif";
          ctx.textAlign = "center";
          ctx.textBaseline = "middle";
          ctx.fillText(Math.round(value) + "%", center.x, center.y);
          ctx.restore();
        });
      });
    },
  };

  function mins(value) {
    return (Math.round(value * 10) / 10).toFixed(1);
  }

  function pct(value) {
    return (value * 100).toFixed(1) + "%";
  }

  function comma(value) {
    return Number(value).toLocaleString("en-US");
  }

  function fasterRange(lo, hi) {
    if (lo < 0 && hi < 0) {
      return mins(Math.abs(hi)) + " to " + mins(Math.abs(lo)) + " min faster";
    }
    if (lo > 0 && hi > 0) {
      return mins(lo) + " to " + mins(hi) + " min slower";
    }
    return mins(lo) + " to " + mins(hi) + " min";
  }

  function mount(id, config) {
    if (charts[id]) charts[id].destroy();
    charts[id] = new Chart(document.getElementById(id), config);
  }

  function renderCards() {
    const h = data.headlines;
    const cards = [
      {
        cls: "faster",
        label: "Time on the report",
        num: mins(Math.abs(h.reportChange.value)) + " min faster",
        detail: mins(h.reportChange.before) + " to " + mins(h.reportChange.after) + " min, same mix",
        ci: "95% CI " + fasterRange(h.reportChange.lo, h.reportChange.hi),
      },
      {
        cls: "faster",
        label: "Report turnaround",
        num: mins(Math.abs(h.turnaroundChange.value)) + " min faster",
        detail: mins(h.turnaroundChange.before) + " to " + mins(h.turnaroundChange.after) + " min, same mix",
        ci: "95% CI " + fasterRange(h.turnaroundChange.lo, h.turnaroundChange.hi),
      },
      {
        cls: "",
        label: "AI impressions accepted",
        num: pct(h.aiAcceptance.value),
        detail: "After launch",
        ci: "95% CI " + pct(h.aiAcceptance.lo) + " to " + pct(h.aiAcceptance.hi),
      },
      {
        cls: "",
        label: "Templates used",
        num: pct(h.templateUsage.value),
        detail: "After launch",
        ci: "95% CI " + pct(h.templateUsage.lo) + " to " + pct(h.templateUsage.hi),
      },
    ];
    document.getElementById("cards").innerHTML = cards
      .map(function (card) {
        return (
          '<article class="card ' + card.cls + '">' +
          '<p class="label">' + card.label + "</p>" +
          '<p class="num">' + card.num + "</p>" +
          '<p class="detail">' + card.detail + "</p>" +
          '<p class="ci">' + card.ci + "</p>" +
          "</article>"
        );
      })
      .join("");
    document.getElementById("quiet").textContent =
      comma(data.meta.nStudies) +
      " studies in the window. Last 2 days still loading, excluded.";
    document.getElementById("words-note").textContent =
      "Words dictated is the median word count. It moved from " +
      Math.round(h.wordsBefore) +
      " to " +
      Math.round(h.wordsAfter.value) +
      " because MRI reports are longer.";
  }

  function renderTrend(slice) {
    const weeks = slice.weekly;
    document.getElementById("cap-trend").textContent =
      document.getElementById("modality").value === "All"
        ? "Median minutes from exam complete to report signed. The band is a 95% interval. This line is the raw median, so more MRI after the launch pulls it up."
        : "Median minutes from exam complete to report signed for this modality. The band is a 95% interval.";
    mount("trend", {
      type: "line",
      data: {
        labels: weeks.map(function (row) { return row.week; }),
        datasets: [
          {
            label: "High",
            data: weeks.map(function (row) { return row.hi; }),
            borderWidth: 0,
            pointRadius: 0,
            fill: false,
          },
          {
            label: "Low",
            data: weeks.map(function (row) { return row.lo; }),
            borderWidth: 0,
            pointRadius: 0,
            backgroundColor: POWDER,
            fill: "-1",
          },
          {
            label: "Median",
            data: weeks.map(function (row) { return row.median; }),
            borderColor: NAVY,
            backgroundColor: NAVY,
            borderWidth: 2,
            pointRadius: 0,
            pointHitRadius: 8,
            tension: 0.25,
            spanGaps: true,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: "index", intersect: false },
        plugins: {
          legend: {
            display: true,
            labels: {
              boxWidth: 14,
              filter: function (item) { return item.datasetIndex === 2; },
            },
          },
          launchLine: { week: data.meta.launch },
          tooltip: {
            filter: function (item) { return item.datasetIndex === 2; },
            callbacks: {
              label: function (item) {
                const row = weeks[item.dataIndex];
                if (row.tooFew || row.lo == null) {
                  return mins(row.median) + " min, too few studies";
                }
                return mins(row.median) + " min (95% CI " + mins(row.lo) + " to " + mins(row.hi) + ")";
              },
            },
          },
        },
        scales: {
          x: {
            grid: { display: false },
            ticks: {
              maxRotation: 0,
              autoSkip: false,
              callback: function (value, index) {
                const label = this.getLabelForValue(value);
                if (label === data.meta.launch || index % 8 === 0) return label.slice(5);
                return "";
              },
            },
          },
          y: {
            title: { display: true, text: "Minutes" },
            grid: { color: "rgba(27, 42, 65, 0.06)" },
          },
        },
      },
      plugins: [launchPlugin],
    });
  }

  function slopePanel(title, before, after, tone) {
    const vals = [before.value, after.value, before.lo, before.hi, after.lo, after.hi].filter(function (v) {
      return v != null;
    });
    let low = Math.min.apply(null, vals);
    let high = Math.max.apply(null, vals);
    const pad = (high - low || 1) * 0.45;
    low = Math.max(0, low - pad);
    high = high + pad;
    const w = 340;
    const h = 250;
    const left = 46;
    const right = 16;
    const top = 58;
    const bottom = 36;
    const y = function (v) {
      return top + (h - top - bottom) * (1 - (v - low) / (high - low));
    };
    const x1 = left + 70;
    const x2 = w - right - 70;
    const color = tone === "slower" ? ROSE : GREEN;
    const word = tone === "slower" ? "slower" : "faster";
    const delta = Math.abs(after.value - before.value);
    function whisker(x, row) {
      if (row.lo == null || row.hi == null) return "";
      return (
        '<line x1="' + x + '" y1="' + y(row.lo) + '" x2="' + x + '" y2="' + y(row.hi) + '" stroke="' + NAVY + '" stroke-width="1.4"/>' +
        '<line x1="' + (x - 6) + '" y1="' + y(row.lo) + '" x2="' + (x + 6) + '" y2="' + y(row.lo) + '" stroke="' + NAVY + '"/>' +
        '<line x1="' + (x - 6) + '" y1="' + y(row.hi) + '" x2="' + (x + 6) + '" y2="' + y(row.hi) + '" stroke="' + NAVY + '"/>'
      );
    }
    const ticks = [low, (low + high) / 2, high];
    const grid = ticks
      .map(function (tick) {
        return (
          '<line x1="' + left + '" y1="' + y(tick) + '" x2="' + (w - right) + '" y2="' + y(tick) + '" stroke="rgba(27,42,65,0.08)"/>' +
          '<text x="' + (left - 6) + '" y="' + (y(tick) + 4) + '" text-anchor="end" font-size="11" fill="#3E5168">' + mins(tick) + "</text>"
        );
      })
      .join("");
    return (
      '<svg viewBox="0 0 ' + w + " " + h + '" class="compare-svg" role="img">' +
      '<rect x="0.5" y="0.5" width="' + (w - 1) + '" height="' + (h - 1) + '" rx="12" fill="#fff" stroke="' + color + '" stroke-width="1.5"/>' +
      '<text x="16" y="24" font-size="14" font-weight="650" fill="' + NAVY + '">' + title + "</text>" +
      '<text x="16" y="44" font-size="13" fill="' + color + '">' + mins(delta) + " min " + word + "</text>" +
      grid +
      '<line x1="' + x1 + '" y1="' + y(before.value) + '" x2="' + x2 + '" y2="' + y(after.value) + '" stroke="' + color + '" stroke-width="2.5"/>' +
      whisker(x1, before) +
      whisker(x2, after) +
      '<circle cx="' + x1 + '" cy="' + y(before.value) + '" r="5.5" fill="' + color + '"/>' +
      '<circle cx="' + x2 + '" cy="' + y(after.value) + '" r="5.5" fill="' + color + '"/>' +
      '<text x="' + x1 + '" y="' + (y(before.value) - 12) + '" text-anchor="middle" font-size="12" fill="' + NAVY + '">' + mins(before.value) + "</text>" +
      '<text x="' + x2 + '" y="' + (y(after.value) - 12) + '" text-anchor="middle" font-size="12" fill="' + NAVY + '">' + mins(after.value) + "</text>" +
      '<text x="' + x1 + '" y="' + (h - 14) + '" text-anchor="middle" font-size="12" fill="#3E5168">Before</text>' +
      '<text x="' + x2 + '" y="' + (h - 14) + '" text-anchor="middle" font-size="12" fill="#3E5168">After</text>' +
      "</svg>"
    );
  }

  function renderCompare(slice, name) {
    const cmp = slice.compare;
    const note = document.getElementById("cap-compare");
    let html = "";
    if (cmp.mode === "mix") {
      note.textContent =
        "Raw median went from " + mins(cmp.rawBefore.value) + " to " + mins(cmp.rawAfter.value) +
        " minutes because MRI rose from " + pct(data.meta.mriBefore) + " to " + pct(data.meta.mriAfter) +
        " of studies. The same mix went from " + mins(cmp.adjBefore.value) + " to " + mins(cmp.adjAfter.value) + " minutes.";
      html =
        '<div class="pair">' +
        slopePanel("Raw median", cmp.rawBefore, cmp.rawAfter, "slower") +
        slopePanel("Same mix", cmp.adjBefore, cmp.adjAfter, "faster") +
        "</div>";
    } else {
      const slower = cmp.rawAfter.value > cmp.rawBefore.value;
      note.textContent =
        "One modality, so there is no mix to adjust. Median turnaround went from " +
        mins(cmp.rawBefore.value) + " to " + mins(cmp.rawAfter.value) + " minutes.";
      html = slopePanel(name + " median", cmp.rawBefore, cmp.rawAfter, slower ? "slower" : "faster");
    }
    document.getElementById("compare").innerHTML = html;
  }

  function heatColor(t) {
    const a = [111, 163, 214];
    const b = [27, 42, 65];
    const rgb = a.map(function (channel, i) {
      return Math.round(channel + (b[i] - channel) * t);
    });
    return { css: "rgb(" + rgb.join(",") + ")", text: t > 0.62 ? "#fff" : NAVY };
  }

  function renderHeat(slice) {
    const cells = {};
    slice.heatmap.forEach(function (cell) {
      cells[cell.dow + "-" + cell.hour] = cell;
    });
    const usable = slice.heatmap.filter(function (cell) { return !cell.tooFew; });
    const values = usable.map(function (cell) { return cell.median; });
    const min = Math.min.apply(null, values);
    const max = Math.max.apply(null, values);
    const grey = slice.heatmap.filter(function (cell) { return cell.tooFew; }).length;
    document.getElementById("cap-heat").textContent =
      "Median turnaround in minutes. Hatched cells have fewer than 30 studies (" + grey + " of " + slice.heatmap.length + ").";
    let html = '<div class="heat">';
    html += '<span></span>';
    for (let hour = 0; hour < 24; hour += 1) {
      html += '<span class="hour">' + hour + "</span>";
    }
    DAYS.forEach(function (day, dow) {
      html += '<span class="day">' + day + "</span>";
      for (let hour = 0; hour < 24; hour += 1) {
        const cell = cells[dow + "-" + hour];
        if (!cell || cell.tooFew) {
          const n = cell ? cell.n : 0;
          html += '<div class="heat-empty" title="' + day + " " + hour + ':00, too few studies, n=' + n + '"></div>';
        } else {
          const t = max === min ? 0.5 : (cell.median - min) / (max - min);
          const color = heatColor(t);
          html +=
            '<div style="background:' + color.css + ";color:" + color.text + '" title="' +
            day + " " + hour + ":00, " + mins(cell.median) + " min, n=" + cell.n + '">' +
            Math.round(cell.median) + "</div>";
        }
      }
    });
    html += "</div>";
    html +=
      '<div class="heat-legend"><span class="swatch heat-empty"></span> too few studies <span class="ramp"></span> ' +
      Math.round(min) + " to " + Math.round(max) + " min</div>";
    document.getElementById("heat").innerHTML = html;
  }

  function renderSites(slice) {
    const sites = slice.sites;
    document.getElementById("cap-sites").textContent =
      "Median turnaround. Whiskers are 95% intervals. The dashed line is the group median. Grey means too few studies.";
    const hi = Math.max.apply(
      null,
      [slice.groupMedian].concat(
        sites.map(function (site) { return site.hi || site.median || 0; })
      )
    );
    mount("sites", {
      type: "bar",
      data: {
        labels: sites.map(function (site) { return site.name; }),
        datasets: [
          {
            data: sites.map(function (site) { return site.median == null ? 0 : site.median; }),
            lo: sites.map(function (site) { return site.lo; }),
            hi: sites.map(function (site) { return site.hi; }),
            group: slice.groupMedian,
            backgroundColor: sites.map(function (site) { return site.tooFew ? GREY : NAVY; }),
            borderRadius: 6,
            barThickness: 18,
          },
        ],
      },
      options: {
        indexAxis: "y",
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: function (item) {
                const site = sites[item.dataIndex];
                if (site.tooFew) return "too few studies (n=" + site.n + ")";
                return mins(site.median) + " min (95% CI " + mins(site.lo) + " to " + mins(site.hi) + ")";
              },
            },
          },
        },
        scales: {
          x: {
            beginAtZero: true,
            suggestedMax: hi * 1.08,
            title: { display: true, text: "Minutes" },
            grid: { color: "rgba(27, 42, 65, 0.06)" },
          },
          y: {
            grid: { display: false },
            ticks: {
              callback: function (value) {
                const site = sites[value];
                if (site.tooFew) return [site.name, "too few studies"];
                return site.name;
              },
            },
          },
        },
      },
      plugins: [sitePlugin],
    });
  }

  function renderBoxes(slice) {
    const present = MODS.filter(function (name) {
      return slice.boxes.some(function (row) { return row.modality === name; });
    });
    document.getElementById("cap-box").textContent =
      "Minutes from report started to signed, before and after the launch. Whiskers are the 10th and 90th percentiles. A heavy tail sits beyond them.";
    const rows = slice.boxes.filter(function (row) { return !row.tooFew; });
    const max = Math.max.apply(null, rows.map(function (row) { return row.p90; }).concat([1])) * 1.12;
    const w = 640;
    const h = 280;
    const padL = 42;
    const padR = 12;
    const padT = 18;
    const padB = 36;
    const plotH = h - padT - padB;
    const y = function (v) {
      return padT + plotH * (1 - v / max);
    };
    const groupW = (w - padL - padR) / Math.max(present.length, 1);
    let body = "";
    [0, 0.25, 0.5, 0.75, 1].forEach(function (share) {
      const value = max * share;
      body +=
        '<line x1="' + padL + '" y1="' + y(value) + '" x2="' + (w - padR) + '" y2="' + y(value) + '" stroke="rgba(27,42,65,0.08)"/>' +
        '<text x="' + (padL - 6) + '" y="' + (y(value) + 4) + '" text-anchor="end" font-size="11" fill="#3E5168">' + Math.round(value) + "</text>";
    });
    present.forEach(function (name, index) {
      const before = slice.boxes.find(function (row) { return row.modality === name && row.period === "before"; });
      const after = slice.boxes.find(function (row) { return row.modality === name && row.period === "after"; });
      const cx = padL + groupW * index + groupW / 2;
      body += boxMark(before, cx - 34, y);
      body += boxMark(after, cx + 6, y);
      body += '<text x="' + cx + '" y="' + (h - 12) + '" text-anchor="middle" font-size="13" fill="' + NAVY + '">' + name + "</text>";
    });
    document.getElementById("boxes").innerHTML =
      '<svg viewBox="0 0 ' + w + " " + h + '" class="box-svg" role="img">' + body + "</svg>" +
      '<div class="box-legend"><span><i class="before"></i>Before</span><span><i class="after"></i>After</span></div>';
  }

  function boxMark(row, x, y) {
    if (!row) return "";
    if (row.tooFew) {
      return '<text x="' + (x + 8) + '" y="' + y(0) + '" font-size="10" fill="#3E5168">too few</text>';
    }
    const fill = row.period === "before" ? "rgba(167,199,231,0.95)" : NAVY;
    const stroke = NAVY;
    const mid = row.period === "before" ? NAVY : "#F4F7FB";
    const top = y(row.p75);
    const height = Math.max(y(row.p25) - y(row.p75), 1);
    return (
      '<line x1="' + (x + 14) + '" y1="' + y(row.p10) + '" x2="' + (x + 14) + '" y2="' + y(row.p90) + '" stroke="' + stroke + '"/>' +
      '<line x1="' + (x + 8) + '" y1="' + y(row.p90) + '" x2="' + (x + 20) + '" y2="' + y(row.p90) + '" stroke="' + stroke + '"/>' +
      '<line x1="' + (x + 8) + '" y1="' + y(row.p10) + '" x2="' + (x + 20) + '" y2="' + y(row.p10) + '" stroke="' + stroke + '"/>' +
      '<rect x="' + x + '" y="' + top + '" width="28" height="' + height + '" rx="3" fill="' + fill + '" stroke="' + stroke + '"/>' +
      '<line x1="' + x + '" y1="' + y(row.p50) + '" x2="' + (x + 28) + '" y2="' + y(row.p50) + '" stroke="' + mid + '" stroke-width="2"/>'
    );
  }

  function renderAi(slice) {
    const rows = slice.ai.filter(function (row) { return !row.tooFew; });
    const hidden = slice.ai.length - rows.length;
    document.getElementById("cap-ai").textContent =
      hidden > 0
        ? "Share of impressions after the launch. " + hidden + " specialties are left off because they have fewer than 30 studies."
        : "Share of impressions after the launch.";
    const share = function (row, key) {
      return row.n ? (row[key] / row.n) * 100 : 0;
    };
    mount("ai", {
      type: "bar",
      data: {
        labels: rows.map(function (row) { return row.specialty; }),
        datasets: [
          { label: "Accepted", data: rows.map(function (row) { return share(row, "accepted"); }), backgroundColor: NAVY },
          { label: "Edited", data: rows.map(function (row) { return share(row, "edited"); }), backgroundColor: "#A7C7E7" },
          { label: "Rejected", data: rows.map(function (row) { return share(row, "rejected"); }), backgroundColor: "#8AA0B8" },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { position: "bottom", labels: { boxWidth: 12 } },
          tooltip: {
            callbacks: {
              label: function (item) {
                return item.dataset.label + " " + item.parsed.y.toFixed(1) + "%";
              },
            },
          },
        },
        scales: {
          x: { stacked: true, grid: { display: false } },
          y: {
            stacked: true,
            max: 100,
            ticks: { callback: function (value) { return value + "%"; } },
            grid: { color: "rgba(27, 42, 65, 0.06)" },
          },
        },
      },
      plugins: [aiLabels],
    });
  }

  function render() {
    const name = document.getElementById("modality").value;
    const slice = data.slices[name];
    document.getElementById("showing").textContent =
      name === "All"
        ? "Charts show all modalities. The headline cards stay on the full group."
        : "Charts show " + name + " only. The headline cards stay on the full group.";
    renderTrend(slice);
    renderCompare(slice, name);
    renderHeat(slice);
    renderSites(slice);
    renderBoxes(slice);
    renderAi(slice);
  }

  renderCards();
  document.getElementById("modality").addEventListener("change", render);
  render();
})();
