from django.db import migrations

SEED = [
    ("Mama Put Kitchen", "Rice (50kg)", 2, "delivered"),
    ("Kilimani Grocers", "Cooking oil (20L)", 5, "pending"),
    ("Arusha Fresh Mart", "Maize flour (2kg)", 40, "dispatched"),
]


def seed(apps, schema_editor):
    Order = apps.get_model("orders", "Order")
    Order.objects.bulk_create(Order(customer=c, item=i, quantity=q, status=s) for c, i, q, s in SEED)


def unseed(apps, schema_editor):
    apps.get_model("orders", "Order").objects.filter(customer__in=[row[0] for row in SEED]).delete()


class Migration(migrations.Migration):
    dependencies = [("orders", "0001_initial")]

    operations = [migrations.RunPython(seed, unseed)]
