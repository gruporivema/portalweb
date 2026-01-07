from django.shortcuts import render

def menu_view(request):
    """
    Main menu view - displays the home page
    Add @login_required decorator when authentication is implemented
    """
    return render(request, 'Menu/home.html') 