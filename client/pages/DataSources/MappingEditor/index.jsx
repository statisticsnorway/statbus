import React from 'react'
import { arrayOf, func, shape, string } from 'prop-types'

import colors from 'helpers/colors'
import Item from './Item'
import MappingItem from './MappingItem'
import styles from './styles.pcss'

const resetSelection = ({ hovered }) => ({
  left: undefined,
  right: undefined,
  dragStarted: false,
  hovered,
})

class MappingsEditor extends React.Component {
  static propTypes = {
    attributes: arrayOf(string).isRequired,
    columns: arrayOf(shape({
      name: string.isRequired,
      localizeKey: string.isRequired,
    }).isRequired).isRequired,
    value: arrayOf(arrayOf(string.isRequired).isRequired),
    mandatoryColumns: arrayOf(string),
    onChange: func.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    value: [],
    mandatoryColumns: [],
  }

  state = {
    left: undefined,
    right: undefined,
    dragStarted: false,
    hovered: undefined,
  }

  componentWillReceiveProps(nextProps) {
    const newAttrib =
      this.state.left !== undefined &&
      nextProps.attributes.find(attr => attr === this.state.left) === undefined
    const newColumn =
      this.state.right !== undefined &&
      nextProps.columns.find(col => col.name === this.state.right) === undefined
    if (newAttrib || newColumn) this.setState(resetSelection)
  }

  getOther(prop) {
    return prop === 'left' ? this.state.right : this.state.left
  }

  mouseUpIsBeingTracked(prop) {
    return this.state.dragStarted && this.getOther(prop)
  }

  handleAdd(prop, value) {
    const pair = prop === 'left' ? [value, this.state.right] : [this.state.left, value]
    const duplicate = this.props.value.find(m => m[0] === pair[0] && m[1] === pair[1])
    if (duplicate === undefined) {
      const nextValue = this.props.value
        .filter(m => m[0] !== pair[0] && m[1] !== pair[1])
        .concat([pair])
      this.setState(resetSelection, () => {
        this.props.onChange(nextValue)
      })
    } else {
      this.setState(resetSelection)
    }
  }

  handleRemove = (attribute, column) => () => {
    const value = this.props.value.filter(([attr, col]) => attr !== attribute || col !== column)
    this.props.onChange(value)
  }

  handleMouseDown = (prop, value) => (e) => {
    e.preventDefault()
    this.setState({
      right: undefined,
      left: undefined,
      [prop]: value,
      dragStarted: true,
    })
  }

  handleMouseUp = (prop, value) => (e) => {
    e.preventDefault()
    document.removeEventListener('mouseup', this.handleMouseUpOutside, false)
    if (this.mouseUpIsBeingTracked(prop)) this.handleAdd(prop, value)
    else this.setState(resetSelection)
  }

  handleMouseUpOutside = () => {
    this.setState(resetSelection)
  }

  handleMouseEnter = (prop, value) => () => {
    this.setState({ hovered: { [prop]: value } }, () => {
      if (this.mouseUpIsBeingTracked(prop)) {
        document.removeEventListener('mouseup', this.handleMouseUpOutside, false)
      }
    })
  }

  handleMouseLeave = () => {
    if (this.state.dragStarted) {
      document.addEventListener('mouseup', this.handleMouseUpOutside, false)
    }
    this.setState({ hovered: undefined })
  }

  handleClick = (prop, value) => () => {
    if (!this.state[prop]) this.setState({ [prop]: value })
    else if (this.getOther(prop)) this.handleAdd(prop, value)
  }

  renderItem(prop, value, label) {
    const adopt = f => f(prop, value)
    const index = this.props.value.findIndex(x => x[prop === 'left' ? 0 : 1] === value)
    const { hovered } = this.state
    return (
      <Item
        key={value}
        id={`${prop}_${value}`}
        text={label || value}
        selected={this.state[prop] === value}
        onClick={adopt(this.handleClick)}
        onMouseDown={adopt(this.handleMouseDown)}
        onMouseUp={adopt(this.handleMouseUp)}
        onMouseEnter={adopt(this.handleMouseEnter)}
        onMouseLeave={this.handleMouseLeave}
        hovered={hovered !== undefined && hovered[prop] === value}
        pointing={index >= 0 ? (prop === 'left' ? 'right' : 'left') : prop}
        color={index >= 0 ? colors[index % colors.length] : 'grey'}
      />
    )
  }

  render() {
    const { attributes, columns, value: mappings, mandatoryColumns, localize } = this.props
    const labelColumn = key =>
      key.includes('.')
        ? key
          .split('.')
          .map((x, i) => (i === 0 && mandatoryColumns.includes(x) ? `${localize(x)}*` : localize(x)))
          .join(' > ')
        : mandatoryColumns.includes(key) ? `${localize(key)}*` : localize(key)
    return (
      <div className={styles.root}>
        <div className={styles['mappings-root']}>
          <div className={styles['mappings-attribs']}>
            {attributes.map(attr => this.renderItem('left', attr))}
          </div>
          <div className={styles['mappings-columns']}>
            {columns.map(col => this.renderItem('right', col.name, labelColumn(col.localizeKey)))}
          </div>
        </div>
        <div className={styles['values-root']}>
          {mappings.map(([attribute, column], i) => (
            <MappingItem
              key={`${attribute}-${column}`}
              attribute={attribute}
              column={labelColumn(columns.find(c => c.name === column).localizeKey)}
              onClick={this.handleRemove(attribute, column)}
              color={colors[i % colors.length]}
            />
          ))}
        </div>
      </div>
    )
  }
}

export default MappingsEditor
