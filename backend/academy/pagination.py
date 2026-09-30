"""Bounded pagination that preserves the API's existing JSON array shape."""

from urllib.parse import urlencode

from rest_framework import serializers
from rest_framework.response import Response


class ListWindowSerializer(serializers.Serializer):
    limit = serializers.IntegerField(min_value=1, max_value=500, default=200)
    offset = serializers.IntegerField(min_value=0, max_value=100000, default=0)


def list_window(request, *, default_limit=200, max_limit=500):
    """Return a validated ``(limit, offset)`` pair for array-shaped endpoints."""
    params = ListWindowSerializer(data=request.query_params)
    params.is_valid(raise_exception=True)
    limit = params.validated_data['limit'] if 'limit' in request.query_params else default_limit
    if limit > max_limit:
        raise serializers.ValidationError(
            {'limit': f'Ensure this value is less than or equal to {max_limit}.'}
        )
    return limit, params.validated_data['offset']


def add_list_window_headers(request, response, *, limit, offset, more):
    """Attach pagination headers without changing the response body shape."""
    response['X-Page-Limit'] = str(limit)
    response['X-Page-Offset'] = str(offset)
    if more:
        params = request.query_params.copy()
        params['limit'] = limit
        params['offset'] = offset + limit
        response['X-Next-Offset'] = str(offset + limit)
        response['Link'] = f'<{request.path}?{urlencode(params)}>; rel="next"'
    return response


def list_response(
    request,
    queryset,
    serializer_class,
    *,
    context=None,
    default_limit=200,
    max_limit=500,
):
    """Serializes a bounded list window and attaches pagination metadata to the response."""
    limit, offset = list_window(
        request,
        default_limit=default_limit,
        max_limit=max_limit,
    )
    if not queryset.ordered:
        queryset = queryset.order_by('pk')
    # Add a unique tie-breaker to model default ordering for stable pages.
    else:
        ordering = queryset.query.order_by or queryset.model._meta.ordering
        queryset = queryset.order_by(*ordering, 'pk')
    rows = list(queryset[offset : offset + limit + 1])
    more = len(rows) > limit
    response = Response(
        serializer_class(
            rows[:limit],
            many=True,
            context={'request': request, **(context or {})},
        ).data
    )
    return add_list_window_headers(
        request,
        response,
        limit=limit,
        offset=offset,
        more=more,
    )
