// SPDX-License-Identifier: AGPL-3.0-or-later
package art;
import cards.Card;
import render.Palette;

/** Asset names follow the canonical Card.code mapping, never sheet position guesses. */
class CardArt {
	public static inline var WIDTH=200;
	public static inline var HEIGHT=280;
	public static function path(card:Card):String return 'cards/faces/${card.code}.png';
	public static function texture(card:Null<Card>,palette:Palette):h3d.mat.Texture {
		return FoyerArt.surface(card==null?"cards/back.png":path(card),palette,100,140,0,1,true).toIndexTexture(true,false);
	}
}
