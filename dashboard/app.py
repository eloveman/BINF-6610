"""Assignment 10: a Dash app over the week-9 runs database.
AI was used in the completion of this assignment
Usage:  python3 dashboard/app.py runs.db [port]
"""
import os
import sqlite3
import sys
from urllib.parse import parse_qs

import dash_ag_grid as dag
import pandas as pd
import plotly.express as px
from dash import Dash, Input, Output, State, ctx, dcc, html

DB = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8050
HERE = os.path.dirname(os.path.abspath(__file__))


SAMPLES_SQL = """
SELECT rs.sample_id, rs.condition, s.phenotype, s.is_synthetic_phenotype
FROM run_samples AS rs
JOIN samples AS s ON s.sample_id = rs.sample_id
WHERE rs.run_id = ?
ORDER BY rs.sample_id
"""

SITES_SQL = """
SELECT chrom, pos, ref, alt, qual, filter
FROM variants
WHERE run_id = ?
ORDER BY chrom, pos
"""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def query(sql, params=()):
    """Open the database, run one query, close it (one connection per call,
    because Dash runs each callback in its own thread)."""
    con = sqlite3.connect(DB)
    try:
        return pd.read_sql_query(sql, con, params=params)
    finally:
        con.close()


def records(df):
    """DataFrame -> rows for AG Grid, with NaN turned into None (JSON null)."""
    return df.astype(object).where(df.notna(), None).to_dict("records")


def grid(grid_id, df):
    return dag.AgGrid(
        id=grid_id,
        rowData=records(df),
        columnDefs=[{"field": c} for c in df.columns],
        columnSize="sizeToFit",
    )


def run_from(search):
    """'?run=abc' -> 'abc' (or None)."""
    values = parse_qs((search or "").lstrip("?")).get("run")
    return values[0] if values else None


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------
def runs_page():
    with open(os.path.join(HERE, "..", "db", "queries", "q1.sql")) as f:
        con = sqlite3.connect(DB)
        try:
            runs = pd.read_sql_query(f.read(), con)
        finally:
            con.close()

    links = html.Ul([
        html.Li(dcc.Link(str(r), href=f"/results?run={r}"))
        for r in runs["run_id"]
    ])
    return html.Div([
        html.H1("Variant-call runs"),
        html.P("Open a run to see its samples, sites and plots."),
        links,
        grid("runs-table", runs),
    ])


def results_page(run_id):
    samples = query(SAMPLES_SQL, (run_id,))
    sites = query(SITES_SQL, (run_id,))

    # plot-filter: number of sites per filter value, written as stored
    counts = sites["filter"].value_counts().reset_index()
    counts.columns = ["filter", "n_sites"]
    fig_filter = px.bar(
        counts, x="filter", y="n_sites",
        title="How many sites passed, and why did the others fail?",
    )
    fig_filter.update_xaxes(type="category")

    # plot-qual: raw qual values
    fig_qual = px.histogram(
        sites, x="qual", title="How confident are the calls?")

    # plot-position: raw pos values
    fig_pos = px.histogram(
        sites, x="pos", title="Where along the region are the sites?")

    return html.Div([
        dcc.Link("All runs", href="/"),
        html.H1(f"Run {run_id}"),

        html.H2("Samples"),
        html.P("Phenotypes in this course are synthetic (made up); "
               "is_synthetic_phenotype marks them."),
        grid("samples-table", samples),

        dcc.Graph(id="plot-filter", figure=fig_filter),
        dcc.Graph(id="plot-qual", figure=fig_qual),
        dcc.Graph(id="plot-position", figure=fig_pos),

        html.H2("Sites"),
        html.P("Click a bar in the filter plot to show only its sites."),
        grid("sites-table", sites),
    ])


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = Dash(__name__, suppress_callback_exceptions=True)
app.layout = html.Div([
    dcc.Location(id="url"),
    html.Div(id="page"),
])


@app.callback(Output("page", "children"),
              Input("url", "pathname"),
              Input("url", "search"))
def draw_page(pathname, search):
    if pathname == "/results":
        run_id = run_from(search)
        if run_id is None:
            return html.Div([dcc.Link("All runs", href="/"),
                             html.P("No run given: use /results?run=<run_id>.")])
        return results_page(run_id)
    return runs_page()


@app.callback(Output("sites-table", "rowData"),
              Input("plot-filter", "clickData"),
              State("url", "search"))
def narrow_sites(click_filter, search):
    sites = query(SITES_SQL, (run_from(search),))
    if ctx.triggered_id == "plot-filter" and click_filter:
        point = click_filter["points"][0]
        value = point.get("label", point.get("x"))
        sites = sites[sites["filter"].astype(str) == str(value)]
    return records(sites)


if __name__ == "__main__":
    app.run(port=PORT, debug=True)
