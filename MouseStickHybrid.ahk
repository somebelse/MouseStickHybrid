; Mouse Stick Hybrid Aim (Name WiP)
; Proof of Concept by Morten Ramcke
; Copyright CC0 - no copyright
; version 0.04 2023-02-05
; changes:
;   added more control over push direction
;   separated inner_deadzones for joystick behavior and push behavior (if in doubt make them the same)

; parameters
global_factor := 3                  ;2

mouse_factor := 1                   ;1
quadratic_acceleration := 0         ;0

joystick_factor := 1                ; 1
joystick_linearity := 1             ; 3

radial_modulation_factor := 0       ; local radial speed factor depending on stick position and radial delta. (feels bad with current implementation. PLEASE EXPERIMENT
radial_exponent_factor := 0.5       ; how much outward movement is increased and inward reduced
radial_linearity := 1               ; 1

inner_deadzone_joy := 3.5           ; 4.5
outer_deadzone := 49.8              ; 49
inner_deadzone_push := 3.5          ; 4.5 (keep small to return to center after push)

edge_push_active := true            ; true
edge_control_active := true         ; true
push_linearity := 1                 ; 1.5

smoothing_steps := 3				; 10 (minimum 1)

stick_center := 50					; 50
dt := 1                             ; 4

; new

joystick_polynomial := []           ; a1, a2, a3... for f(x)= 0 + a1*x + a2*x^2 + a3*x^3 + ... with x in [0, 1]
mouse_polynomial := []              ; a1, a2, a3... for f(x)= 0 + a1*x + a2*x^2 + a3*x^3 + ...
derivative_factor := 0              ; just an idea. negative would delay movement, positive would push it forward

radial_polynomial := []             ; a1, a2, a3... for f(x)= 0 + a1*x + a2*x^2 + a3*x^3 + ... with x in [0, 1]

pause_on_release := false           ; disables output while letting go of the stick. Needs touch sensitive stick to work

#SingleInstance Force

; Auto-detect the joystick number if called for:
JoystickNumber := 0
if JoystickNumber <= 0
{
    Loop 16  ; Query each joystick number to find out which ones exist.
    {
        if GetKeyState(A_Index "JoyName")
        {
            JoystickNumber := A_Index
            break
        }
    }
    if JoystickNumber <= 0
    {
        MsgBox "The system does not appear to have any joysticks."
        ExitApp
    }
}

; initialisation
history_dx := Array()
history_dx.length := smoothing_steps
history_dy := Array()
history_dy.length := smoothing_steps
deflection_x := 0
deflection_y := 0
deflection_distance := 0
has_touched := false
livezone_joy := outer_deadzone - inner_deadzone_joy
livezone_push := outer_deadzone - inner_deadzone_push
decimal_residue_x := 0
decimal_residue_y := 0
smoothing_counter := 1
loop smoothing_steps{
	history_dx[A_Index] := 0
	history_dy[A_index] := 0
}
SetTimer(UpdateLoop, dt)


; Main loop to control mouse movement. Repeats until program is stopped.
UpdateLoop(){
    global

    prev_deflection_x := deflection_x
    prev_deflection_y := deflection_y
    prev_deflection_distance := deflection_distance
    deflection_x := GetKeyState(JoystickNumber "JoyU") - stick_center
    deflection_y := (GetKeyState(JoystickNumber "JoyR") - stick_center)
    deflection_distance := sqrt(deflection_x * deflection_x + deflection_y * deflection_y)
    angle := atan2(deflection_y , deflection_x)
    dx := deflection_x - prev_deflection_x
    dy := deflection_y - prev_deflection_y

	history_dx[smoothing_counter] := dx
	history_dy[smoothing_counter] := dy
	average_dx := 0
	average_dy := 0
	loop smoothing_steps{
		average_dx += history_dx[A_Index]
		average_dy += history_dy[A_Index]
	}
	average_dx /= smoothing_steps
	average_dy /= smoothing_steps

    distance_delta := sqrt(average_dx * average_dx + average_dy * average_dy)
    angle_delta := atan2(dy, dx)

    ; deadzones:
    ; outer
    if (deflection_distance >= outer_deadzone){
        ; entering outer
        if (prev_deflection_distance < outer_deadzone){
            has_touched := true
            angle_touch := angle
            push_x := (1 + quadratic_acceleration * distance_delta / dt) * distance_delta * cos(angle_delta - angle) * cos(angle)
            push_y := (1 + quadratic_acceleration * distance_delta / dt) * distance_delta * cos(angle_delta - angle) * sin(angle)
            push := sqrt(push_x * push_x + push_y * push_y)
        }
        if edge_control_active{
            angle_touch := angle
            push_x := push * cos(angle)
            push_y := push * sin(angle)
        }
        magnitude := 1
        ; clip radial delta
        if (cos(angle_delta - angle) > 0){
            normal_x := sin(angle)
            normal_y := - cos(angle)
            dotProduct := normal_x * dx + normal_y * dy
            dx := dotProduct * normal_x
            dy := dotProduct * normal_y
            ; Mouse acceleration should stay untouched
        }
    }else{
        ; inner (Joystick)
        if (deflection_distance < inner_deadzone_joy){
            magnitude := 0
        }else{
            ; "livezone"
            magnitude := (deflection_distance - inner_deadzone_joy) / livezone_joy
        }

    }

    ; mouse behavior
    output_x := mouse_factor * (1 + quadratic_acceleration * distance_delta / dt) * average_dx      ;replaced dx, dy with average_dx, _dy
    output_y := mouse_factor * (1 + quadratic_acceleration * distance_delta / dt) * average_dy

    ; radial modulation behavior HIGHLY WIP
    dotProduct := average_dx * cos(angle) + average_dy * sin(angle)
    radial_dx := dotProduct * cos(angle)
    radial_dy := dotProduct * sin(angle)
    magnitude_radial := magnitude ** radial_linearity

    output_x += radial_modulation_factor * 2 ** (radial_exponent_factor * dotProduct/dt) * magnitude_radial * radial_dx
    output_y += radial_modulation_factor * 2 ** (radial_exponent_factor * dotProduct/dt) * magnitude_radial * radial_dy


    ; joystick behavior
    magnitude_joy := magnitude ** joystick_linearity
    magnitude_x := magnitude_joy * cos(angle)
    magnitude_y := magnitude_joy * sin(angle)
    output_x += joystick_factor * dt * magnitude_x
    output_y += joystick_factor * dt * magnitude_y

    ; edge touch push
    if (has_touched and edge_push_active){
        deflection_touch_axis := deflection_distance * cos(angle - angle_touch)
        if (deflection_touch_axis < inner_deadzone_push){
            has_touched := false
        }else{
            magnitude_push := ((deflection_touch_axis - inner_deadzone_push) / livezone_push) ** push_linearity
            output_x += mouse_factor * magnitude_push * push_x
            output_y += mouse_factor * magnitude_push * push_y
        }

        ; clip when speed to center < 0
        if ((output_x * cos(angle) + output_y * sin(angle)) < 0){
            output_x := 0
            output_y := 0
        }
    }


    output_x *= global_factor
    output_y *= global_factor
    output_x += decimal_residue_x
    output_y += decimal_residue_y
    decimal_residue_x := output_x - Floor(output_x)
    decimal_residue_y := output_y - Floor(output_y)

    ; MouseMove(Floor(output_x), Floor(output_y), 0, "R")
    /*
    DllCall("mouse_event", uint, dwFlags, int, dx ,int, dy, uint, dwData, int, 0)
    */
    DllCall("mouse_event", "uint", 0x1, "int", Floor(output_x), "int", Floor(output_y), "uint", 0, "int", 0)

	if (smoothing_counter < smoothing_steps){
		smoothing_counter++
	}else{
		smoothing_counter := 1
	}

}

/*
vec_radial("float", x, "float", y, "float", theta){
    unitVec_x := cos(theta)
    unitVec_y := sin(theta)
    dotProduct := x * unitVec_x + y * unitVec_y
    radial_x := dotProduct * unitVec_x
    radial_y := dotProduct * unitVec_y
    return radial_x, radial_y
}

vec_circular("float", x, "float", y, "float", theta){
    unitVec_x := - sin(theta)
    unitVec_y := cos(theta)
    dotProduct := x * unitVec_x + y * unitVec_y
    circular_x := dotProduct * unitVec_x
    circular_y := dotProduct * unitVec_y
    return circular_x, circular_y
*/

atan2(y,x) {    ; 4-quadrant atan
   		Return dllcall("msvcrt\atan2","Double",y, "Double",x, "CDECL Double")
	}
