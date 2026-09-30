from django.shortcuts import render


def index(request):
    """Renders the browser-based administration console."""
    return render(request, 'console/index.html')
