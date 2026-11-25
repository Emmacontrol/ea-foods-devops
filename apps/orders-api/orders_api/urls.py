from django.urls import re_path

from orders import views

# The ALB forwards /orders and /orders/* unchanged, so the app serves that path.
# /health is handled by HealthCheckMiddleware.
urlpatterns = [
    re_path(r"^orders/?$", views.list_orders, name="list-orders"),
]
