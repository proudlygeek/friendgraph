function switchBox(hiding, showing){
    hiding.fadeOut('fast', function(){
    	$(showing).fadeIn();
    });
}

$(document).ready(function() {
	$('.alert').fadeIn();
	
	$('#accept').click(function(){ 
		switchBox($('.alert'), $('.btn-login'))
	});

	$('#deny').click(function(){
		switchBox($('.alert'), $('#retry'));
	});

	$('#retry').click(function(){
		switchBox($('#retry'), $('.alert'));
	});
	
});	