import React from 'react'
import { string, bool, func } from 'prop-types'
import { Label } from 'semantic-ui-react'
import styles from './styles.scss'

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
  isRequired,
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
    basic={
      hovered || selected || pointing === 'left' ? false : isRequired ? true : color === 'grey'
    }
    className={`cursor-pointer ${styles.labelBorder}`}
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
  isRequired: bool.isRequired,
}

export default Item
