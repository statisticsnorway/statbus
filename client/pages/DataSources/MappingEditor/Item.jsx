import React from 'react'
import { string, bool, func } from 'prop-types'
import { Label } from 'semantic-ui-react'

const Item = ({
  text,
  selected,
  hovered,
  pointing,
  color,
  onClick,
  onMouseDown,
  onMouseUp,
  onMouseEnter,
  onMouseLeave,
}) => (
  <Label
    onClick={onClick}
    onMouseDown={onMouseDown}
    onMouseUp={onMouseUp}
    onMouseEnter={onMouseEnter}
    onMouseLeave={onMouseLeave}
    color={hovered || selected ? 'blue' : color}
    content={text}
    pointing={pointing}
    basic={hovered || selected ? false : color === 'grey'}
  />
)

Item.propTypes = {
  text: string.isRequired,
  selected: bool.isRequired,
  hovered: bool.isRequired,
  color: string.isRequired,
  pointing: string.isRequired,
  onClick: func.isRequired,
  onMouseDown: func.isRequired,
  onMouseUp: func.isRequired,
  onMouseEnter: func.isRequired,
  onMouseLeave: func.isRequired,
}

export default Item
