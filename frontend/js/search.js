/* ---------------------------------------------------------------------------
 * search.js -- client-side full-text search using MkDocs search_index.json
 * ------------------------------------------------------------------------- */
'use strict';

(function () {
  const queryInput = document.getElementById('search-query');
  const btnSearch = document.getElementById('btn-search');
  const statsEl = document.getElementById('search-stats');
  const resultsEl = document.getElementById('search-results');
  const noticeEl = document.getElementById('search-notice');

  let docs = [];
  let indexLoaded = false;
  let indexError = null;

  function stripHtml(html) {
    if (!html) return '';
    const tmp = document.createElement('div');
    tmp.innerHTML = html;
    return tmp.textContent || tmp.innerText || '';
  }

  function esc(s) {
    if (!s) return '';
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  async function loadIndex() {
    try {
      const resp = await fetch('/docs/search/search_index.json');
      if (!resp.ok) {
        throw new Error(`HTTP ${resp.status}`);
      }
      const data = await resp.json();
      docs = (data.docs || []).map(d => ({
        location: d.location || '',
        title: d.title || 'Untitled',
        text: stripHtml(d.text || '')
      }));
      indexLoaded = true;
      indexError = null;

      // If initial query exists in input, run search
      if (queryInput.value.trim()) {
        performSearch(queryInput.value.trim());
      }
    } catch (e) {
      indexLoaded = false;
      indexError = e;
      noticeEl.hidden = false;
      noticeEl.innerHTML = `
        <h3 style="margin-top:0;">Documentation index not available</h3>
        <p>The search index could not be loaded from <code>/docs/search/search_index.json</code> (${e.message}).</p>
        <p>To generate the search index, build the documentation using:
           <br><code style="display:inline-block;margin-top:0.5rem;padding:0.3rem 0.6rem;background:var(--bg-alt);border-radius:4px;">tools/build_docs.sh</code> or <code style="display:inline-block;margin-top:0.5rem;padding:0.3rem 0.6rem;background:var(--bg-alt);border-radius:4px;">mkdocs build</code>
        </p>`;
    }
  }

  function highlight(text, query) {
    if (!query) return esc(text);
    const escapedQ = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const regex = new RegExp(`(${escapedQ})`, 'gi');
    return esc(text).replace(regex, '<mark>$1</mark>');
  }

  function getSnippet(fullText, query) {
    if (!fullText) return '';
    const qLower = query.toLowerCase();
    const tLower = fullText.toLowerCase();
    const idx = tLower.indexOf(qLower);

    if (idx === -1) {
      return esc(fullText.slice(0, 160)) + (fullText.length > 160 ? '…' : '');
    }

    const start = Math.max(0, idx - 60);
    const end = Math.min(fullText.length, idx + query.length + 80);
    let snippet = (start > 0 ? '…' : '') + fullText.slice(start, end) + (end < fullText.length ? '…' : '');
    return highlight(snippet, query);
  }

  function performSearch(q) {
    if (!indexLoaded) {
      if (indexError) return;
      statsEl.textContent = 'Loading index...';
      return;
    }

    const query = q.trim();
    if (!query) {
      statsEl.textContent = '';
      resultsEl.innerHTML = '';
      return;
    }

    // Update URL query string
    const u = new URL(window.location);
    u.searchParams.set('q', query);
    window.history.replaceState({}, '', u);

    const qLower = query.toLowerCase();
    const terms = qLower.split(/\s+/).filter(Boolean);

    const matches = [];
    for (const d of docs) {
      const titleLower = d.title.toLowerCase();
      const textLower = d.text.toLowerCase();

      // Check if all terms appear in either title or text
      let allMatch = true;
      let score = 0;

      for (const t of terms) {
        const inTitle = titleLower.includes(t);
        const inText = textLower.includes(t);
        if (!inTitle && !inText) {
          allMatch = false;
          break;
        }
        if (inTitle) score += 10;
        if (inText) score += 2;
      }

      if (allMatch) {
        matches.push({ doc: d, score });
      }
    }

    // Sort by relevance score descending
    matches.sort((a, b) => b.score - a.score);

    statsEl.textContent = `${matches.length} result${matches.length === 1 ? '' : 's'} for "${query}"`;

    if (matches.length === 0) {
      resultsEl.innerHTML = `<div class="search-notice">No documentation pages matched "${esc(query)}". Try different keywords or broader terms.</div>`;
      return;
    }

    let html = '';
    matches.slice(0, 50).forEach(m => {
      const d = m.doc;
      const href = `/docs/${d.location}`;
      const titleHighlight = highlight(d.title, terms[0]);
      const snippet = getSnippet(d.text, terms[0]);

      html += `
        <article class="search-item">
          <h3><a href="${href}">${titleHighlight}</a></h3>
          <div class="search-item-location">${esc(d.location || 'index.html')}</div>
          <div class="search-item-snippet">${snippet}</div>
        </article>`;
    });

    resultsEl.innerHTML = html;
  }

  // Handle URL query on load
  const urlParams = new URLSearchParams(window.location.search);
  const initialQ = urlParams.get('q');
  if (initialQ) {
    queryInput.value = initialQ;
  }

  let debounceTimer = null;
  queryInput.addEventListener('input', () => {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      performSearch(queryInput.value);
    }, 200);
  });

  queryInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      clearTimeout(debounceTimer);
      performSearch(queryInput.value);
    }
  });

  if (btnSearch) {
    btnSearch.addEventListener('click', () => {
      performSearch(queryInput.value);
    });
  }

  loadIndex();
})();
