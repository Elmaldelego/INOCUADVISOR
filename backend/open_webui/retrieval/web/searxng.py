import logging
from typing import Optional

import requests
from open_webui.retrieval.web.main import SearchResult, get_filtered_results, SearchParameters
from open_webui.env import SRC_LOG_LEVELS

log = logging.getLogger(__name__)
log.setLevel(SRC_LOG_LEVELS["RAG"])


def search_searxng(
    params : SearchParameters,
    query_url : str,
    **kwargs,
) -> list[SearchResult]:
    """
    Search a SearXNG instance for a given query and return the results as a list of SearchResult objects.

    The function allows passing additional parameters such as language or time_range to tailor the search result.

    Args expected in params:
        query_url (str): The base URL of the SearXNG server.

    Keyword Args:
        language (str): Language filter for the search results; e.g., "en-US". Defaults to an empty string.
        safesearch (int): Safe search filter for safer web results; 0 = off, 1 = moderate, 2 = strict. Defaults to 1 (moderate).
        time_range (str): Time range for filtering results by date; e.g., "2023-04-05..today" or "all-time". Defaults to ''.
        categories: (Optional[list[str]]): Specific categories within which the search should be performed, defaulting to an empty string if not provided.

    Returns:
        list[SearchResult]: A list of SearchResults sorted by relevance score in descending order.

    Raise:
        requests.exceptions.RequestException: If a request error occurs during the search process.
    """

    # Default values for optional parameters are provided as empty strings or None when not specified.
    language = kwargs.get("language")
    safesearch = kwargs.get("safesearch", "1")
    time_range = kwargs.get("time_range", "")
    categories = "".join(kwargs.get("categories", []))

    data = {
        "q": params.query,
        "format": "json",
        "pageno": 1,
        "safesearch": safesearch,
        "language": language,
        "time_range": time_range,
        "categories": categories,
        "theme": "simple",
        "image_proxy": 0,
    }

    # Legacy query format
    if "<query>" in query_url:
        # Strip all query parameters from the URL
        query_url = query_url.split("?")[0]

    log.debug(f"searching {query_url}")

    response = requests.get(
        query_url,
        headers={
            "User-Agent": "Open WebUI (https://github.com/open-webui/open-webui) RAG Bot",
            "Accept": "text/html",
            "Accept-Encoding": "gzip, deflate",
            "Accept-Language": "en-US,en;q=0.5",
            "Connection": "keep-alive",
        },
        params=data,
    )

    response.raise_for_status()  # Raise an exception for HTTP errors.

    json_response = response.json()
    results = json_response.get("results", [])
    sorted_results = sorted(results, key=lambda x: x.get("score", 0), reverse=True)
    sorted_results = get_filtered_results(sorted_results, params)
    return [
        SearchResult(
            link=result["url"], title=result.get("title"), snippet=result.get("content")
        )
        for result in sorted_results[:params.count]
    ]
