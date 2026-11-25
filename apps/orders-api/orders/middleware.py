from django.conf import settings
from django.http import JsonResponse


class HealthCheckMiddleware:
    """Answers GET /health before any other middleware runs.

    - The ALB health check sends the task's private IP as the Host header, which
      Django's ALLOWED_HOSTS check would reject with a 400. Answering here avoids
      having to set ALLOWED_HOSTS = ["*"].
    - It is a liveness check only: it does NOT query the database. If it did, a
      database outage would mark every task unhealthy and ECS would restart them
      all in a loop. Database failures surface as 5xx on /orders instead.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.path == "/health":
            return JsonResponse({"status": "ok", "service": "orders-api", "version": settings.APP_VERSION})
        return self.get_response(request)
