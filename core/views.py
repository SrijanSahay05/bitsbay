from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt

@csrf_exempt
def home(request):
    """
    Simple home view that returns a welcome message
    """
    return JsonResponse({
        'message': 'Welcome to BitsBay API',
        'status': 'success',
        'endpoints': {
            'admin': '/admin/',
            'auth': '/api/auth/',
            'marketplace': '/api/'
        }
    }) 