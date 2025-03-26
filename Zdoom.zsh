#!/usr/bin/env zsh

# ZshDoomClone - A simple top-down shooter in Zsh
# Inspired by Doom, but vastly simpler.

# --- Configuration ---
setopt KSH_ARRAYS # Use 0-based indexing like ksh/bash

# Game Objects
PLAYER_CHAR="웃"
ENEMY_CHAR_IMP="☢" # Imp-like
ENEMY_CHAR_DEMON="☣" # Demon-like
WALL_CHAR="▓"
FLOOR_CHAR="░"
PROJECTILE_CHAR="•"
HEALTH_PACK_CHAR="✚"
AMMO_PACK_CHAR="¤"

# Colors (ANSI)
COLOR_RESET="\e[0m"
COLOR_PLAYER="\e[1;32m"  # Bold Green
COLOR_ENEMY_IMP="\e[1;31m" # Bold Red
COLOR_ENEMY_DEMON="\e[1;35m" # Bold Magenta
COLOR_WALL="\e[0;37m"    # White/Gray
COLOR_FLOOR="\e[2;37m"   # Dim White/Gray
COLOR_PROJECTILE="\e[1;33m" # Bold Yellow
COLOR_HEALTH_PACK="\e[1;32m" # Bold Green
COLOR_AMMO_PACK="\e[1;36m"  # Bold Cyan
COLOR_UI="\e[1;37m"     # Bold White
COLOR_GAMEOVER="\e[1;5;31m" # Bold Blink Red
COLOR_MENU="\e[1;34m"     # Bold Blue

# Game Settings
MAP_WIDTH=40
MAP_HEIGHT=15
INITIAL_PLAYER_HP=100
INITIAL_PLAYER_AMMO=20
ENEMY_IMP_HP=20
ENEMY_DEMON_HP=50
ENEMY_IMP_DAMAGE=5
ENEMY_DEMON_DAMAGE=10
ENEMY_IMP_SCORE=10
ENEMY_DEMON_SCORE=25
HEALTH_PACK_AMOUNT=25
AMMO_PACK_AMOUNT=10
GAME_TICK_DELAY=0.1 # Seconds between game updates

# High Score File
HIGHSCORE_FILE="$HOME/.zshdoom_highscore"

# --- Game State ---
typeset -A player=( [x]=2 [y]=2 [hp]=$INITIAL_PLAYER_HP [ammo]=$INITIAL_PLAYER_AMMO )
typeset -A enemies # Associative array for enemies: enemies[id,key]=value
typeset -A items   # Associative array for items: items[id,key]=value
player_score=0
last_enemy_id=0
last_item_id=0
game_over=false
game_message=""

# --- Map Data ---
# Define the map layout. Add more levels or complexity as desired.
map=(
    "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
    "▓░░░░░░░░░░░░░▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░▓"
    "▓░░░░░░░░░░░░░▓¤░░░░▓░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓"
    "▓░░✚░░░▓▓▓▓▓▓▓▓░░░░░▓░░░░░░▓░░░░░░░░░░▓"
    "▓░░░░░░▓░░░░░░░░░░░░▓▓▓░░▓▓▓░░░░░░░░░░▓"
    "▓░░░░░░▓░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓▓▓▓"
    "▓▓▓▓▓▓▓▓░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░▓"
    "▓░░░░░░░░░░▓░░░░░░░░░░░░░░░░░▓░░░░░░░░▓"
    "▓░░░░░░▓▓▓▓▓░░░░░░░░░░░░░░░░░▓░░░░✚░░░▓"
    "▓░░░░░░▓░░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░▓"
    "▓▓▓▓░░░▓░░░░░░░▓░░░░░░░░░░░░░░░░░░░░░▓"
    "▓░░░░░░▓░░░░░░░▓░░¤░░░░░░░░░░░░░░░░░░▓"
    "▓░░░░░░▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░▓▓▓▓▓▓"
    "▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓"
    "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
)

# --- Utility Functions ---

# Function to place cursor
setpos() {
    print -n "\e[${1};${2}H"
}

# Function to clear screen
cls() {
    print -n "\e[2J\e[H"
}

# Function to hide cursor
hide_cursor() {
    print -n "\e[?25l"
}

# Function to show cursor
show_cursor() {
    print -n "\e[?25h"
}

# Function to get character at map coordinates
get_map_char() {
    local x=$1 y=$2
    # Check bounds
    if (( y < 0 || y >= ${#map[@]} || x < 0 || x >= ${#map[y]} )); then
        echo "$WALL_CHAR" # Treat out of bounds as wall
        return
    fi
    echo "${map[$y]:$x:1}"
}

# Check if a position is occupied (wall, enemy, player)
is_occupied() {
    local x=$1 y=$2 check_player=${3:-true}
    local map_char=$(get_map_char $x $y)
    if [[ "$map_char" == "$WALL_CHAR" ]]; then
        return 0 # Occupied by wall
    fi
    if $check_player && (( player[x] == x && player[y] == y )); then
        return 0 # Occupied by player
    fi
    for id in ${(k)enemies}; do
        # Extract ID from key like "id,x"
        local enemy_id=${id%%,*}
        if (( enemies[$enemy_id,x] == x && enemies[$enemy_id,y] == y )); then
            return 0 # Occupied by enemy
        fi
    done
    return 1 # Not occupied
}

# Find a random empty floor spot
find_empty_spot() {
    local x y found=false
    integer tries=0
    while ! $found && (( tries < 100 )); do
        (( x = RANDOM % MAP_WIDTH ))
        (( y = RANDOM % MAP_HEIGHT ))
        local char=$(get_map_char $x $y)
        if [[ "$char" == "$FLOOR_CHAR" ]] && ! is_occupied $x $y; then
            found=true
            echo "$x $y"
            return 0
        fi
        (( tries++ ))
    done
    return 1 # Failed to find a spot
}

# Spawn an enemy
spawn_enemy() {
    local type=$1
    local coords=$(find_empty_spot)
    if [[ -z "$coords" ]]; then return; fi # No space
    local x=${coords%% *} y=${coords## *}

    (( last_enemy_id++ ))
    local id=$last_enemy_id
    enemies[$id,x]=$x
    enemies[$id,y]=$y
    enemies[$id,type]=$type
    case $type in
        imp)
            enemies[$id,char]=$ENEMY_CHAR_IMP
            enemies[$id,color]=$COLOR_ENEMY_IMP
            enemies[$id,hp]=$ENEMY_IMP_HP
            enemies[$id,damage]=$ENEMY_IMP_DAMAGE
            enemies[$id,score]=$ENEMY_IMP_SCORE
            ;;
        demon)
            enemies[$id,char]=$ENEMY_CHAR_DEMON
            enemies[$id,color]=$COLOR_ENEMY_DEMON
            enemies[$id,hp]=$ENEMY_DEMON_HP
            enemies[$id,damage]=$ENEMY_DEMON_DAMAGE
            enemies[$id,score]=$ENEMY_DEMON_SCORE
            ;;
    esac
}

# Spawn an item
spawn_item() {
    local type=$1
    local coords=$(find_empty_spot)
    if [[ -z "$coords" ]]; then return; fi # No space
    local x=${coords%% *} y=${coords## *}

    # Avoid spawning on existing item
    for item_id in ${(k)items}; do
        local i_id=${item_id%%,*}
        if (( items[$i_id,x] == x && items[$i_id,y] == y )); then
            return # Don't spawn on top of another item
        fi
    done

    (( last_item_id++ ))
    local id=$last_item_id
    items[$id,x]=$x
    items[$id,y]=$y
    items[$id,type]=$type
    case $type in
        health) items[$id,char]=$HEALTH_PACK_CHAR; items[$id,color]=$COLOR_HEALTH_PACK ;;
        ammo)   items[$id,char]=$AMMO_PACK_CHAR;   items[$id,color]=$COLOR_AMMO_PACK ;;
    esac
}

# Cleanup function on exit
cleanup() {
    show_cursor
    stty echo # Restore echo
    stty cooked # Restore cooked mode (vs raw/cbreak)
    print -n "$COLOR_RESET" # Reset colors just in case
    setpos $(stty size | cut -d' ' -f1) 1 # Move cursor to bottom left
    echo "Exited ZshDoomClone."
}

# Load high score
load_highscore() {
    if [[ -f "$HIGHSCORE_FILE" ]]; then
        highscore=$(< "$HIGHSCORE_FILE")
        # Validate if it's a number
        [[ "$highscore" =~ ^[0-9]+$ ]] || highscore=0
    else
        highscore=0
    fi
    echo $highscore
}

# Save high score
save_highscore() {
    local current_highscore=$(load_highscore)
    if (( player_score > current_highscore )); then
        echo $player_score > "$HIGHSCORE_FILE"
        game_message+=" New High Score: $player_score!"
    fi
}

# --- Drawing Functions ---

draw_map() {
    setpos 1 1
    for (( y=0; y<$MAP_HEIGHT; y++ )); do
        for (( x=0; x<$MAP_WIDTH; x++ )); do
            local char=$(get_map_char $x $y)
            if [[ "$char" == "$WALL_CHAR" ]]; then
                print -n "${COLOR_WALL}${WALL_CHAR}${COLOR_RESET}"
            elif [[ "$char" == "$FLOOR_CHAR" ]]; then
                print -n "${COLOR_FLOOR}${FLOOR_CHAR}${COLOR_RESET}"
            else
                # Handle potential other static map chars if needed
                print -n "$char"
            fi
        done
        # Move to next line without printing newline char itself
        setpos $((y + 2)) 1
    done
}

draw_items() {
    for id in ${(k)items}; do
        local item_id=${id%%,*}
        if [[ -n "${items[$item_id,x]}" ]]; then # Check if item still exists
            setpos $(( items[$item_id,y] + 1 )) $(( items[$item_id,x] + 1 ))
            print -n "${items[$item_id,color]}${items[$item_id,char]}${COLOR_RESET}"
        fi
    done
}

draw_enemies() {
    for id in ${(k)enemies}; do
        local enemy_id=${id%%,*}
        if [[ -n "${enemies[$enemy_id,x]}" ]]; then # Check if enemy still exists
            setpos $(( enemies[$enemy_id,y] + 1 )) $(( enemies[$enemy_id,x] + 1 ))
            print -n "${enemies[$enemy_id,color]}${enemies[$enemy_id,char]}${COLOR_RESET}"
        fi
    done
}

draw_player() {
    setpos $(( player[y] + 1 )) $(( player[x] + 1 ))
    print -n "${COLOR_PLAYER}${PLAYER_CHAR}${COLOR_RESET}"
}

draw_ui() {
    setpos $(( MAP_HEIGHT + 2 )) 1
    print -n "${COLOR_UI}HP: ${player[hp]} | Ammo: ${player[ammo]} | Score: ${player_score}${COLOR_RESET}"
    # Clear rest of the line
    print -n "\e[K"

    # Display message if any
    if [[ -n "$game_message" ]]; then
        setpos $(( MAP_HEIGHT + 3 )) 1
        print -n "${COLOR_UI}${game_message}${COLOR_RESET}\e[K"
        # Clear message after one display cycle (or keep it longer if needed)
        # game_message=""
    else
        # Clear the message line if there's no message
        setpos $(( MAP_HEIGHT + 3 )) 1
        print -n "\e[K"
    fi
}

# --- Game Logic ---

move_player() {
    local dx=0 dy=0
    case "$1" in
        w|k) dy=-1 ;;
        s|j) dy=1 ;;
        a|h) dx=-1 ;;
        d|l) dx=1 ;;
        *) return ;; # Ignore other keys for movement
    esac

    local target_x=$(( player[x] + dx ))
    local target_y=$(( player[y] + dy ))

    # Check for wall collision
    local map_char=$(get_map_char $target_x $target_y)
    if [[ "$map_char" == "$WALL_CHAR" ]]; then
        game_message="Ouch! A wall."
        return
    fi

    # Check for enemy collision (player bumps into enemy)
    for id in ${(k)enemies}; do
        local enemy_id=${id%%,*}
        if [[ -n "${enemies[$enemy_id,x]}" ]]; then # Check if enemy exists
             if (( enemies[$enemy_id,x] == target_x && enemies[$enemy_id,y] == target_y )); then
                 game_message="Blocked by an enemy!"
                 return # Can't move into enemy space
             fi
        fi
    done

    # Move player
    player[x]=$target_x
    player[y]=$target_y
    game_message="" # Clear message on successful move

    # Check for item pickup
    for id in ${(k)items}; do
       local item_id=${id%%,*}
       if [[ -n "${items[$item_id,x]}" ]]; then # Check if item exists
            if (( items[$item_id,x] == player[x] && items[$item_id,y] == player[y] )); then
                case "${items[$item_id,type]}" in
                    health)
                        (( player[hp] += HEALTH_PACK_AMOUNT ))
                        if (( player[hp] > INITIAL_PLAYER_HP )); then player[hp]=$INITIAL_PLAYER_HP; fi
                        game_message="Picked up Health! (+${HEALTH_PACK_AMOUNT} HP)"
                        ;;
                    ammo)
                        (( player[ammo] += AMMO_PACK_AMOUNT ))
                        game_message="Picked up Ammo! (+${AMMO_PACK_AMOUNT})"
                        ;;
                esac
                # Remove item - unset all keys for this ID
                for key in ${(k)items}; do
                   [[ $key == $item_id,* ]] && unset items[$key]
                done
                # Redraw the floor tile where the item was
                setpos $(( player[y] + 1 )) $(( player[x] + 1 ))
                print -n "${COLOR_FLOOR}${FLOOR_CHAR}${COLOR_RESET}"
                break # Pick up only one item per step
            fi
       fi
    done
}

shoot() {
    local shoot_dir=$1
    if (( player[ammo] <= 0 )); then
        game_message="Click! Out of ammo."
        return
    fi
    (( player[ammo]-- ))
    game_message="BANG!"

    local dx=0 dy=0
    case "$shoot_dir" in
        W|K) dy=-1 ;; # Uppercase for shooting
        S|J) dy=1 ;;
        A|H) dx=-1 ;;
        D|L) dx=1 ;;
        *) game_message="Invalid direction?"; return ;; # Should not happen if called correctly
    esac

    # Projectile starts one step away from player
    local px=$(( player[x] + dx ))
    local py=$(( player[y] + dy ))

    # Simulate projectile travel
    for (( i=0; i<10; i++ )); do # Max range of 10 tiles
        local map_char=$(get_map_char $px $py)
        if [[ "$map_char" == "$WALL_CHAR" ]]; then
            game_message="Shot hit the wall."
            # Optional: Show impact briefly
            setpos $(( py + 1 )) $(( px + 1 ))
            print -n "${COLOR_PROJECTILE}*${COLOR_RESET}"
            sleep 0.05 # Brief flash
            # Redraw original wall
            setpos $(( py + 1 )) $(( px + 1 ))
            print -n "${COLOR_WALL}${WALL_CHAR}${COLOR_RESET}"
            return
        fi

        # Check for enemy hit
        local hit_enemy=false
        for id in ${(k)enemies}; do
            local enemy_id=${id%%,*}
            if [[ -n "${enemies[$enemy_id,x]}" ]]; then # Check if enemy exists
                 if (( enemies[$enemy_id,x] == px && enemies[$enemy_id,y] == py )); then
                     hit_enemy=true
                     # Damage enemy
                     (( enemies[$enemy_id,hp] -= 10 )) # Simple fixed damage
                     game_message="Hit ${enemies[$enemy_id,type]}!"

                     # Check if enemy died
                     if (( enemies[$enemy_id,hp] <= 0 )); then
                         game_message+=" Enemy killed! (+${enemies[$enemy_id,score]} Score)"
                         (( player_score += enemies[$enemy_id,score] ))
                         # Remove enemy - unset all keys for this ID
                         local dead_x=${enemies[$enemy_id,x]} dead_y=${enemies[$enemy_id,y]}
                         for key in ${(k)enemies}; do
                            [[ $key == $enemy_id,* ]] && unset enemies[$key]
                         done
                         # Redraw floor where enemy was
                         setpos $(( dead_y + 1 )) $(( dead_x + 1 ))
                         print -n "${COLOR_FLOOR}${FLOOR_CHAR}${COLOR_RESET}"

                         # Chance to spawn item on death
                         if (( RANDOM % 5 < 2 )); then # 40% chance
                            if (( RANDOM % 2 == 0 )); then spawn_item health; else spawn_item ammo; fi
                         fi
                     else
                         # Show hit flash on enemy
                         setpos $(( py + 1 )) $(( px + 1 ))
                         print -n "${COLOR_PROJECTILE}${enemies[$enemy_id,char]}${COLOR_RESET}"
                         sleep 0.05
                         # Redraw enemy normally (will happen in main loop redraw)
                     fi
                     return # Stop projectile after hitting an enemy
                 fi
            fi
        done

        # Draw projectile moving
        setpos $(( py + 1 )) $(( px + 1 ))
        print -n "${COLOR_PROJECTILE}${PROJECTILE_CHAR}${COLOR_RESET}"
        sleep 0.02 # Faster projectile speed
        # Erase projectile's previous position (redraw floor/item) - handled by main redraw loop

        # Move projectile
        (( px += dx ))
        (( py += dy ))
    done
    game_message="Shot fizzled out." # If it reached max range
}


move_enemies() {
    local ids_to_process=(${(k)enemies}) # Get snapshot of keys

    for id in $ids_to_process; do
        local enemy_id=${id%%,*}
        # Ensure enemy still exists (wasn't just killed)
        if [[ -z "${enemies[$enemy_id,x]}" ]]; then continue; fi

        local ex=${enemies[$enemy_id,x]} ey=${enemies[$enemy_id,y]}
        local target_x=$ex target_y=$ey

        # Simple AI: Move towards player if within ~8 distance, otherwise random move?
        local dist_x=$(( player[x] - ex ))
        local dist_y=$(( player[y] - ey ))
        local distance=$(( dist_x*dist_x + dist_y*dist_y )) # Squared distance check is faster

        if (( distance < 64 )); then # If within sqrt(64)=8 tiles approx
            # Try to move closer
            local moved=false
            # Prioritize axis with greater distance
            if (( abs(dist_x) > abs(dist_y) )); then
                # Try horizontal move first
                if (( dist_x > 0 )); then (( target_x = ex + 1 )); else (( target_x = ex - 1 )); fi
                target_y=$ey
                if ! is_occupied $target_x $target_y false; then moved=true; fi

                # If horizontal failed or wasn't the primary direction, try vertical
                if ! $moved && (( dist_y != 0 )); then
                     target_x=$ex
                     if (( dist_y > 0 )); then (( target_y = ey + 1 )); else (( target_y = ey - 1 )); fi
                     if ! is_occupied $target_x $target_y false; then moved=true; fi
                fi
            else
                # Try vertical move first
                 if (( dist_y > 0 )); then (( target_y = ey + 1 )); else (( target_y = ey - 1 )); fi
                 target_x=$ex
                 if ! is_occupied $target_x $target_y false; then moved=true; fi

                 # If vertical failed or wasn't the primary direction, try horizontal
                 if ! $moved && (( dist_x != 0 )); then
                      target_y=$ey
                      if (( dist_x > 0 )); then (( target_x = ex + 1 )); else (( target_x = ex - 1 )); fi
                      if ! is_occupied $target_x $target_y false; then moved=true; fi
                 fi
            fi

             # If cannot move towards player, maybe a random step? (can get stuck)
             # For simplicity, let's just stay put if blocked directly towards player.
             if ! $moved; then
                 target_x=$ex
                 target_y=$ey
             fi

        else
             # Random movement (optional, makes game harder/more dynamic)
             # if (( RANDOM % 5 == 0 )); then # Only move sometimes randomly
             #    local rand_dir=$(( RANDOM % 4 ))
             #    local rdx=0 rdy=0
             #    case $rand_dir in
             #        0) rdy=-1 ;; 1) rdy=1 ;; 2) rdx=-1 ;; 3) rdx=1 ;;
             #    esac
             #    local nrx=$(( ex + rdx )) nry=$(( ey + rdy ))
             #    if ! is_occupied $nrx $nry false; then
             #        target_x=$nrx target_y=$nry
             #    fi
             # fi
             target_x=$ex target_y=$ey # Stay put if far away
        fi

        # Check if target position is the player -> Attack!
        if (( target_x == player[x] && target_y == player[y] )); then
            (( player[hp] -= enemies[$enemy_id,damage] ))
            game_message="Hit by ${enemies[$enemy_id,type]}! (-${enemies[$enemy_id,damage]} HP)"
            if (( player[hp] <= 0 )); then
                player[hp]=0
                game_over=true
                game_message="YOU DIED! Final Score: $player_score"
                return # Exit function immediately on game over
            fi
            # Don't move enemy into player space after attack
            target_x=$ex
            target_y=$ey
        fi

        # Update enemy position if it changed
        enemies[$enemy_id,x]=$target_x
        enemies[$enemy_id,y]=$target_y
    done
}


# --- Main Menu ---
show_menu() {
    local highscore=$(load_highscore)
    cls
    setpos 3 5
    print -P "${COLOR_MENU}===== ZshDoomClone ====="
    setpos 5 5
    print -P "${COLOR_UI}A simple top-down shooter"
    setpos 7 5
    print -P "High Score: ${COLOR_PLAYER}${highscore}${COLOR_RESET}"
    setpos 9 5
    print -P "${COLOR_UI}[S] Start Game"
    setpos 10 5
    print -P "${COLOR_UI}[Q] Quit"
    setpos 12 5
    print -P "${COLOR_UI}Controls:"
    setpos 13 5
    print -P "${COLOR_UI} Move: W, A, S, D (or K, H, J, L)"
    setpos 14 5
    print -P "${COLOR_UI} Shoot: Shift + Move Key (e.g., Shift+W or K)"
    setpos 15 5
    print -P "${COLOR_UI} Quit Game: Ctrl+C"

    while true; do
        read -k 1 choice
        case "$choice" in
            s|S) return 0 ;; # Start game
            q|Q) return 1 ;; # Quit
        esac
    done
}

# --- Game Loop ---
game_loop() {
    # Initial setup
    cls
    hide_cursor
    stty -echo # Don't echo typed characters
    stty cbreak # Get chars immediately (alternative to raw)

    # Spawn initial enemies/items
    spawn_enemy imp
    spawn_enemy imp
    spawn_enemy demon
    spawn_item health
    spawn_item ammo

    while ! $game_over; do
        # --- Draw Frame ---
        # Set cursor to home and draw static map (less flicker than full clear)
        # setpos 1 1
        # draw_map # Can be slow, optimize by drawing only dynamic things if needed
        # For simplicity and robustness, we redraw everything
        cls
        draw_map
        draw_items
        draw_enemies
        draw_player
        draw_ui

        # --- Read Input (with timeout) ---
        local key=""
        read -k 1 -t $GAME_TICK_DELAY key # Read 1 char, timeout after delay

        # --- Process Input ---
        # Check for quit signal (Ctrl+C is handled by trap)
        case "$key" in
            [wasdkhjl]) move_player $key ;;
            [WASDKHJL]) shoot $key ;; # Use uppercase for shooting
             # Add other keys if needed (e.g., pause 'p')
             ?) game_message="" ;; # Clear message on unrecognized key
        esac

        # --- Update Game State ---
        if ! $game_over; then # Don't move enemies if player just died
            move_enemies
        fi

        # Check win condition? (e.g., kill all enemies)
        # local num_enemies=${#${(k)enemies}} # Doesn't work quite right with assoc keys
        local enemy_count=0
        for id in ${(k)enemies}; do
             [[ $id == *,x ]] && (( enemy_count++ ))
        done

        if (( enemy_count == 0 )); then
             # Option 1: End game
             # game_over=true
             # game_message="VICTORY! All enemies defeated! Score: $player_score"

             # Option 2: Spawn more enemies (wave system)
             game_message="Wave cleared! Prepare for more..."
             draw_ui # Update UI immediately
             sleep 2
             spawn_enemy imp; spawn_enemy imp; spawn_enemy imp
             spawn_enemy demon
             if (( RANDOM % 3 == 0 )); then spawn_item health; fi
             if (( RANDOM % 2 == 0 )); then spawn_item ammo; fi
             game_message="" # Clear message
        fi

        # --- Delay ---
        # The read timeout provides the main delay
        # sleep $GAME_TICK_DELAY # Can add explicit sleep if read timeout is unreliable

    done

    # --- Game Over ---
    save_highscore
    setpos $(( MAP_HEIGHT + 4 )) 1
    print -P "${COLOR_GAMEOVER}${game_message}${COLOR_RESET}"
    setpos $(( MAP_HEIGHT + 5 )) 1
    print -P "${COLOR_UI}Press any key to return to menu...${COLOR_RESET}"
    read -k 1 # Wait for key press
}

# --- Main Execution ---

# Setup trap to restore terminal settings on exit
trap cleanup EXIT INT TERM

# Show menu and decide action
while true; do
     show_menu
    if (( $? == 0 )); then
        # Reset game state before starting
        player=( [x]=2 [y]=2 [hp]=$INITIAL_PLAYER_HP [ammo]=$INITIAL_PLAYER_AMMO )
        enemies=()
        items=()
        player_score=0
        last_enemy_id=0
        last_item_id=0
        game_over=false
        game_message=""

        game_loop
    else
        break # Quit chosen from menu
    fi
done

# Cleanup is handled by the trap

exit 0
