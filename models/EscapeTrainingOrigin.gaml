/***
* Name: EscapeTraining1
* Author: kevinchapuis
* Description: Training model of evacuation strategies and catastroph mitigation in urban area
* Tags: ESCAPE, Evacuation strategy, Hazard mitigation
***/

model EscapeTraining1

global {
	
	// PARAMETERS
	float hazard_probability;
	float hazard_max_size <- 200#m;
	
	pair indiv_threshold_gauss;
	int nb_of_people;
	
	bool road_impact <- false;
	int nb_exit;
	
	string the_alert_strategy;
	list<string> the_strategies <- list("DEFAULT","STAGED","SPATIAL");
	
	graph<geometry, geometry> road_network;
	map<road,float> road_weights <- [];
	
	// BUILDING RELATED USELESS ATTRIBUTE
	pair floor_range <- 2.4#m::3.4#m;
	pair activity_range <- 2#h::6#h;
	int max_floor <- 10;
	
	// Number of road sections
	int nb_xy_intersect <- 10;
	
	geometry shape <- square(500#m);
	
	float step <- 2#sec;
	
	/*
	 * OUTPUT SECTION
	 */
	int safe_inhabitant <- 0; // Number of people that reach an evacuation point
	int evacuating_inhabitant <- 0;  // Number of people that want to reach an evacuation point
	
	float evacuation_time <- 0.0#sec; // Time elapse until the first alert has been sent
	bool evacuation <-false;
	
	/*
	 * USER TRIGGERED DISASTER
	 */
	user_command disaster action: create_disaster;
	action create_disaster {
		point disasterPoint <- #user_location;
		create hazard with: [location::disasterPoint,proba_occur::1.0];
	}
	
	init {
		
		/*
		 * CREATION OF THE WORLD : TO BE SAVED TO FILES AND DELETED FOR THE TRAINING VERSION
		 */
		
		float x_width <- shape.width / nb_xy_intersect;
		float y_height <- shape.height / nb_xy_intersect;
		float corridors <- (x_width < y_height ? x_width : y_height) / 10;
		list<geometry> lines <- [];
	
		
		// N/S or S/N roads
		loop x from:1 to:nb_xy_intersect-1 {
			lines <+ flip(0.5) ? 
				line({x*x_width,0}, {x*x_width,world.shape.height}) : 
				line({x*x_width,world.shape.height}, {x*x_width,0});
		}
		// O/E or E/O roads
		loop y from:1 to:nb_xy_intersect-1 {
			lines <+ flip(0.5) ?
				line({0,y*y_height}, {world.shape.width,y*y_height}) :
				line({world.shape.width,y*y_height}, {0,y*y_height});
		}
		
		// Buildings
		int total_capacity <- 0;
		loop i_x from:0 to:nb_xy_intersect-1 {
			loop i_y from:0 to:nb_xy_intersect-1 {
				create building {
					point x_point <- {i_x*x_width+corridors, i_y*y_height+corridors};
					float x_length <- x_width-2*corridors;
					float y_length <- y_height-2*corridors;
					shape <- polygon(x_point, x_point+{x_length,0}, 
						x_point+{x_length,y_length}, x_point+{0,y_length}); 	
					
					int nb_of_floor <- rnd(1,max_floor);
					building_height <- nb_of_floor * rnd(floor_range.key,floor_range.value)#m;
					max_capacity <- int(nb_of_floor * shape.area / (10#m^2));
					total_capacity <- total_capacity + max_capacity;
				}
			}
		}
		
		// Create network of road
		lines <- clean_network(lines,0.0,true,true);
		loop l over:lines{
			create road {
				shape <- l;
				capacity <- l.perimeter;
			}
		}		
		
		road_network <- as_edge_graph(road);
		road_weights <- road as_map (each::each.shape.perimeter);
		
		/*
		 *  Evacuation point
		 *  TODO: move to shapefile with the rest
		 */
		loop while: nb_exit > 0 {
			int position <- rnd(1,nb_xy_intersect-1);
			point the_exit;
			if(flip(0.5)){
				the_exit <- {position*x_width,flip(0.5) ? 0 : world.shape.height};
			} else {
				the_exit <- {flip(0.5) ? 0 : world.shape.width, position*y_height};
			}
			
			bool no_duplicate <- empty(evacuation_point where (each.location = the_exit));
			bool valide_exit <- not(empty(road where (each.shape.points[1] = the_exit))); 
			
			if (no_duplicate and valide_exit){
				create evacuation_point with:[location::the_exit];
				nb_exit <- nb_exit - 1;
			}
		}
		
		create inhabitant number:nb_of_people{
			
			list<building> available_places <- building where not(each.max_capacity - length(each.occupants) = 0);
			bool in_building <- length(available_places) = 0 ? false : true;  
			if(in_building){
				current_place <- one_of(available_places);
				location <- any_location_in(current_place);
			} else {
				location <- any_location_in(one_of(road));
			} 
			
		}
	
		create hazard with:[proba_occur::hazard_probability];
		create crisis_manager with:[predicated::rnd(1.0)];
		
		/*
		 * Export world section
		 */
		save road to:"../includes/grid_network.shp" type:shp;
		save building to:"../includes/buildings.shp" type:shp;
		save evacuation_point to:"../includes/evac_points.shp" type:shp;
		
	}
	
	reflex update_indicators {
		safe_inhabitant <- sum(evacuation_point collect each.count_exit);
		evacuating_inhabitant <- inhabitant count each.alerted;
		evacuation_time <- evacuation ? evacuation_time + step : evacuation_time;
	}
	
	reflex stop_simu when:empty(inhabitant) {
		do pause;
	}
	
}

// -------------------- END OF INIT ---------------------- //

/*
 * Main agent to be manipulated: entity that will decide which evacuation strategy to used
 */
species crisis_manager {
	
	float predicated;
	
	alert_strategy strategy;
	
	init {
		
		switch the_alert_strategy {
			match "DEFAULT" {
				create alert_strategy returns:strategies; 
				strategy <- strategies[0];
			}
			match "STAGED" {
				create staged_strategy returns:strategies; 
				strategy <- strategies[0];
			}
			match "SPATIAL" {
				create spatial_strategy returns:strategies; 
				strategy <- strategies[0];
			}
		}
		
	}
	
	/*
	 * Send alert when: hazard is confirmed (any intensity exept none) or randomly according to prediction
	 * 
	 * Sended alert is a level from 0 to 1 according to hazard intensity
	 * 
	 */
	reflex send_alert when: (hazard count (each.intensity > 0.0) > 0 or
		flip(predicated * mean(hazard collect each.proba_occur))) and strategy.alert_conditional() {
			
		float hazard_level <- sum(hazard collect (each.intensity)) / length(hazard);
		float alert_level <- hazard_level = 0.0 ? predicated : predicated*hazard_level;
		
		ask strategy.alert_target() { do receive_alert(alert_level); }
		
		world.evacuation <- true;
		write "ALERT SENT AT "+current_date.hour+":"+current_date.minute+":"+current_date.second
			+"\nSTRATEGY: "+string(strategy);
	}
	
}

// -------------- //
//   STRATEGIES   //
// -------------- //

species alert_strategy {
	
	date last_alert;
	
	bool alert_conditional {
		if(last_alert = nil){
			last_alert <- current_date;
			return true;
		} else {
			return false;
		}
	}
	
	list<inhabitant> alert_target {
		return list(inhabitant);
	}
	
}

species staged_strategy parent:alert_strategy {
	
	int nb_stage <- 4;
	list<list<inhabitant>> staged_target;
	
	date last_alert;
	float alert_range <- 5#mn;
	
	init {
		list<inhabitant> buffer <- list(inhabitant);
		int nb_per_stage <- int(length(buffer) / nb_stage);
		loop times:nb_stage-1 {
			list<inhabitant> this_stage <- nb_per_stage among buffer;
			buffer >>- this_stage; 
			staged_target <+ this_stage;
		}
		staged_target <+ buffer;
	}
	
	bool alert_conditional {
		return not(empty(staged_target)) and 
			(last_alert = nil or (current_date - last_alert = alert_range));
	}
	
	list<inhabitant> alert_target {
		container<inhabitant> targets <- staged_target[0];
		staged_target >- targets;
		return targets;
	}
	
}

species spatial_strategy parent:alert_strategy {
	
	geometry d_buffer;
	float distance_buffer <- 100#m;
	int buffered_inhabitants;
	float buffer_tolerance <- 0.1;
	
	int iter <- 1;
	
	bool alert_conditional {
		return length(inhabitant overlapping d_buffer) < (buffered_inhabitants * buffer_tolerance) or iter = 1;
	}
	
	list<inhabitant> alert_target {
		d_buffer <- hazard[0] buffer (distance_buffer * iter);
		list<inhabitant> trgt <- inhabitant overlapping d_buffer;
		buffered_inhabitants <- length(trgt); 
		iter <- iter + 1;
		return trgt;
	}
	
}

// -------------- //
//   INHABITANT   //
// -------------- //

species inhabitant skills:[moving] {
	
	rgb color <- rnd_color(255);
	float tall <- rnd(1.5#m, 1.9#m);
	
	building current_place;
	float speed <- 4#km/#h;
	
	float alert_threshold <- gauss(float(indiv_threshold_gauss.key),float(indiv_threshold_gauss.value));
	bool alerted <- false;
	evacuation_point evac_target;
	
	/*
	 * perceived alert trigger evacuation point choice if the level if equal or better than alert_threshold
	 * 
	 * People do choose the closest exit
	 *  
	 */
	action receive_alert(float level){
		alerted <- true;
		if(level >= alert_threshold){
			evac_target <- evacuation_point with_min_of (each distance_to self);
		} else {
			alert_threshold <- alert_threshold + alert_threshold / (1-0.95);
		}
	}
	
	/*
	 * Evacue goto choosen evacuation point
	 */
	reflex evacuate when:alerted and evacuation_point != nil {
		do goto target:evac_target on:road_network move_weights:road_weights;
		road the_current_road <- road(current_edge);
		if(the_current_road != nil){
			the_current_road.users <- the_current_road.users + 1;
		}
		if(location = evac_target.location){
			ask evac_target {do evacue_inhabitant(myself);}
		}
	}
	
	aspect default{
		draw pyramid(tall) color:color;
		draw sphere(0.2#m) at: location + {0,0,tall} color:color;
	}
	
	aspect not_in_building {
		if(current_place = nil){
			draw pyramid(tall) color:color;
			draw sphere(0.2#m) at: location + {0,0,tall} color:color;
		}
	}
	
}

// ------------------ //
//   HAZARD RELATED   //
// ------------------ //

species hazard {
	
	float proba_occur;
	
	float intensity;
	
	bool evolve <- false;
	
	/*
	 * Trigger the hazard with random intensity
	 */
	reflex triggered when: flip(proba_occur) {
		if(location = nil){ location <- any_location_in(world);}
		intensity <- rnd(1.0);
		// NEVER OCCUR AGAIN
		proba_occur <- 0.0;
	}
	
	/*
	 * Intensity decrease
	 */
	reflex evolve when: evolve and intensity > 0.0 {
		intensity <- intensity <= 0.01 ? 0.0 : intensity * 0.99;
	}
	
	aspect default {
		draw sphere(hazard_max_size*intensity) at: {location.x,location.y,-hazard_max_size*intensity} color:#red;
	}
	
}

species evacuation_point {
	
	int count_exit <- 0;
	
	/*
	 * Count and kill people that have been evacuated
	 */
	action evacue_inhabitant(inhabitant people) {
		count_exit <- count_exit + 1;
		ask people {do die;}
	}
	
	aspect default {
		draw circle(10#m) color:#green;
	}
	
}

// ---------------- //
//   ENVIRONEMENT   //
// ---------------- //

species road {

	int users;
	float capacity;
	
	float display_size;
	
	reflex disrupt when: road_impact and not(empty(hazard)) {
		loop h over:hazard {
			if(self distance_to h < h.intensity*hazard_max_size){
				do die;
			}
		}
	}
	
	reflex update_weights {
		road_weights[self] <- shape.perimeter * exp(-users/capacity);
		display_size <- users/capacity*4#m;
		users <- 0;
	}
	
	aspect default{
		draw shape width: display_size color:rgb(55+200*users/capacity,0,0);
	}	
}

/*
 * USELESS FOR NOW
 */
species building {
	
	float building_height;
	int max_capacity;
	
	list<inhabitant> occupants;
	
	aspect default {
		//draw shape depth:length(occupants)/max_capacity*building_height color:#grey;
		draw shape depth:building_height border:#black color:#white;
	}
	
}

experiment my_experiment type:gui {
	parameter "Number of people" var: nb_of_people min: 100 init:5000;
	parameter "Number of exit" var:nb_exit min:1 init:4;
	parameter "Hazard probability" var:hazard_probability init:0.01;
	parameter "Average evacuation individual threshold" var:indiv_threshold_gauss type:pair init:0.0::0.0;
	parameter "Alert Strategy" var:the_alert_strategy init:"Default" among:the_strategies;
	output{
		display my_display type:opengl { 
			species inhabitant;
			species road;
			species evacuation_point;
			species hazard transparency:0.7;
			species building transparency:0.5;
		}
		
		monitor safe_inhabitant value:safe_inhabitant;
		monitor number_of_evacuates value:evacuating_inhabitant;
		monitor evacuation_time value:evacuation_time	;
	}
}
