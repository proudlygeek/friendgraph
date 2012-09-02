$(document).ready(function() {
    navigator.geolocation.getCurrentPosition(function(pos) {
        function panFriend() {
            var id = this.id;
            var coords = [friends[id].latitude, friends[id].longitude];
            map.panTo(coords);
            friends[id].marker.openPopup();

            return false;
        }

        function panMe() {
            var coords = [pos.coords.latitude, pos.coords.longitude];
            
            map.panTo(coords);
            me.marker.openPopup();

            return false;
        }


        function updatePosition(position)
        {
            coordsData = {
                'latitude'  : position.coords.latitude,
                'longitude' : position.coords.longitude
            };

            $.ajax({
                type: 'POST',
                url: '/update-my-position',
                data: coordsData
            });
        }

        var userPosition = [pos.coords.latitude, pos.coords.longitude];
        var map = L.map('map').setView(userPosition, 12);
        

        // var myIcon = L.icon({
        //     iconUrl: me.image,
        // });

        var marker = L.marker(userPosition, {
            title: "You are Here!", 
            // icon: myIcon
        }).addTo(map);

        me.marker = marker
            .bindPopup("<h4>" + me.user_info.info.name + 
                       "</h4><img src='" + me.image + "' />")
            .openPopup();

        $(friends).each(function(idx, friend) {
            // var friendIcon = L.icon({
            //     iconUrl: friend.image,
            // });

            var marker = L.marker([friend.latitude, friend.longitude], {
                title: friend.user_info.info.name, 
                // icon:friendIcon
            }).addTo(map);

            // Save marker reference
            friend.marker = marker
                .bindPopup("<h4>" + friend.user_info.info.name + 
                           "</h4><img src='" + friend.image + "' />");
        });

        function onLocationFound(e) {
            var radius = e.accuracy / 2;

            L.marker(e.latlng)
                .addTo(map)
                .bindPopup("You are within " + radius + " meters from this point")
                .openPopup();

            L.circle(e.latlng, radius).addTo(map);
        }

        function onLocationError(e) {
            alert(e.message);
        }

        map.on('locationfound', onLocationFound);
        map.on('locationerror', onLocationError);      

        L.tileLayer('http://{s}.tile.cloudmade.com/40de62a33dcc422fb3685e0879969574/997/256/{z}/{x}/{y}.png', {
            attribution: 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors, <a href="http://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, Imagery © <a href="http://cloudmade.com">CloudMade</a>',
            maxZoom: 18
        }).addTo(map);

        updatePosition(pos);

        $('.friend').click(panFriend);
        $('.find-me').click(panMe);
    });
});





