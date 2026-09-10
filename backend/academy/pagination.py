"""Bounded pagination that preserves the API's existing JSON array shape."""

from urllib.parse import urlencode

from rest_framework import serializers
from rest_framework.response import Response


class ListWindowSerializer(serializers.Serializer):
    limit = serializers.IntegerField(min_value=1, max_value=500, default=200)
    offset = serializers.IntegerField(min_value=0, max_value=100000, default=0)


def list_response(request, queryset, serializer_class, *, context=None):
    params = ListWindowSerializer(data=request.query_params)
    params.is_valid(raise_exception=True)
    limit = params.validated_data['limit']
    offset = params.validated_data['offset']
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
    response['X-Page-Limit'] = str(limit)
    response['X-Page-Offset'] = str(offset)
    if more:
        params = request.query_params.copy()
        params['limit'] = limit
        params['offset'] = offset + limit
        response['X-Next-Offset'] = str(offset + limit)
        response['Link'] = f'<{request.path}?{urlencode(params)}>; rel="next"'
    return response
