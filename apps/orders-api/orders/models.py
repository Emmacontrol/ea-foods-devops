from django.db import models


class Order(models.Model):
    customer = models.CharField(max_length=100)
    item = models.CharField(max_length=100)
    quantity = models.PositiveIntegerField(default=1)
    status = models.CharField(max_length=20, default="pending")
    created_at = models.DateTimeField(auto_now_add=True)
