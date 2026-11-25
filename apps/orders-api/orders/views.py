from django.http import JsonResponse
from django.views.decorators.http import require_GET

from .models import Order


@require_GET
def list_orders(request):
    orders = list(Order.objects.order_by("id").values("id", "customer", "item", "quantity", "status", "created_at"))
    return JsonResponse({"count": len(orders), "orders": orders})
