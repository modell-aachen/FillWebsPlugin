jQuery(function($) {
    $('form.fillwebsform').livequery(function(){
        var $this = $(this);
        var confirmation = $this.find('input[name="confirmation"]').remove().val();
        $this.submit(function(){
            var $this = $(this);
            if(confirmation && !confirm(confirmation.replace('\$srcweb', $this.find('input[name="srcweb"]').val()).replace('\$resetweb', $this.find('input[name="resetweb"]').val()).replace('\$target', $this.find('input[name="target"]').val()))) {
                return false;
            }
            if($this.hasClass('blockUI')) {
                $.blockUI();
            } else {
                $this.children().block();
            }
        });
    });
});
