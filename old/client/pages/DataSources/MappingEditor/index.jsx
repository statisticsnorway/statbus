import React from 'react'
import { arrayOf, func, shape, string } from 'prop-types'
import { Grid, Label, Header, Segment, Message } from 'semantic-ui-react'
import * as R from 'ramda'
import { groupByToArray } from '/helpers/enumerable'

import ListWithDnd from '/components/ListWithDnd'
import { hasValue } from '/helpers/validation'
import colors from '/helpers/colors'
import Item from './Item.jsx'
import { tryFieldIsRequired, tryFieldIsRequiredForUpdate, getFieldsForUpdate } from '../model.js'
import styles from './styles.scss'

const getPropByDot = (target, path) => {
  if (!path.length) return target
  const props = path.split('.')

  if (!target.hasOwnProperty(props[0])) throw new Error(`target has not got field: ${props[0]}`)

  const next = target[props[0]]
  return getPropByDot(next, props.slice(1).join('.'))
}

const isStatUnitRequired = (path) => {
  const [field] = path.split('.')
  if (!initialStatMap.hasOwnProperty(field)) {
    return window.__initialStateFromServer.mandatoryFields.StatUnit[field]
  }

  const isFieldRequired = window.__initialStateFromServer.mandatoryFields.StatUnit[field]
  if (!isFieldRequired) return false

  try {
    return getPropByDot(initialStatMap, path)
  } catch (e) {
    return false
  }
}

const initialStatMap = {
  Address: window.__initialStateFromServer.mandatoryFields.Addresses,
  ActualAddress: window.__initialStateFromServer.mandatoryFields.Addresses,
  Persons: window.__initialStateFromServer.mandatoryFields.Person,
  Activities: window.__initialStateFromServer.mandatoryFields.Activity,
}

const resetSelection = ({ hovered }) => ({
  left: undefined,
  right: undefined,
  dragStarted: false,
  hovered,
})

const multipleAssignmentVariables = []

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
    mapping: shape({}).isRequired,
    attribs: shape({}).isRequired,
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
    isUpdateValid: false,
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

  getAttributeColor(prop, value) {
    const leftIndex = this.props.attributes.indexOf(prop === 'left' ? value : this.props.value.find(([, col]) => col === value)[0])
    return colors[(leftIndex + 1) % colors.length]
  }

  mouseUpIsBeingTracked(prop) {
    return this.state.dragStarted && this.getOther(prop)
  }

  handleAdd(prop, value) {
    const pair = prop === 'left' ? [value, this.state.right] : [this.state.left, value]
    const duplicate = this.props.value.find(m => m[0] === pair[0] && m[1] === pair[1])
    if (duplicate === undefined) {
      const nextValue = multipleAssignmentVariables.includes(pair[1])
        ? this.props.value.concat([pair])
        : this.props.value.filter(m => m[1] !== pair[1]).concat([pair])
      this.setState(resetSelection, () => {
        this.props.onChange(nextValue)
      })
    } else {
      this.setState(resetSelection)
    }
  }

  checkIsUpdateValid = () => {
    this.setState({
      isUpdateValid: this.props.isUpdate
        ? tryFieldIsRequiredForUpdate(this.props.mapping.value)
        : false,
    })
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

  // eslint-disable-next-line class-methods-use-this
  functionTryFieldIsRequired(cols, field, variablesMapping) {
    return tryFieldIsRequired(
      cols.map(x => x.name),
      field.split('.')[0],
      variablesMapping,
    )
  }

  handleMouseEnter = (prop, value) => () => {
    this.setState({ hovered: { [prop]: value } }, () => {
      if (this.mouseUpIsBeingTracked(prop)) {
        document.removeEventListener('mouseup', this.handleMouseUpOutside, false)
      }
    })
  }

  handleMouseLeave = () => {
    this.checkIsUpdateValid()

    if (this.state.dragStarted) {
      document.addEventListener('mouseup', this.handleMouseUpOutside, false)
    }
    this.setState({ hovered: undefined })
  }

  handleClick = (prop, value) => () => {
    if (!this.state[prop]) this.setState({ [prop]: value })
    else if (this.getOther(prop)) this.handleAdd(prop, value)
  }

  renderItem(prop, value, label = '') {
    if (typeof label !== 'string') throw new TypeError('Label must be a string')
    const isRequired = isStatUnitRequired(value)
    const adopt = f => f(prop, value)
    const index = this.props.value.findIndex(x => x[prop === 'left' ? 0 : 1] === value)
    const { hovered, isUpdateValid } = this.state
    const bool1 =
      prop === 'left' || index >= 0
        ? this.getAttributeColor(prop, value)
        : this.props.isUpdate && isUpdateValid
          ? 'grey'
          : isRequired
            ? 'red'
            : 'grey'
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
        isRequired={this.props.isUpdate && isUpdateValid ? false : isRequired}
        color={bool1}
      />
    )
  }

  componentDidMount() {
    this.checkIsUpdateValid()
  }

  render() {
    const {
      attributes,
      columns,
      value: mappings,
      mandatoryColumns: mandatoryCols,
      onChange,
      localize,
      mapping,
      attribs,
      isUpdate,
    } = this.props

    const variablesForUpdate = getFieldsForUpdate()

    const mandatoryColsArr = isUpdate ? variablesForUpdate : mandatoryCols

    const labelColumn = key =>
      key && key.includes('.')
        ? key
          .split('.')
          .map((x, i) =>
            i === 0 && (mandatoryColsArr.includes(x) || mandatoryColsArr.includes(key))
              ? `${localize(x)}*`
              : localize(x))
          .join(' > ')
        : mandatoryColsArr.includes(key)
          ? `${localize(key)}*`
          : localize(key)
    const renderValueItem = ([attr, col]) => {
      const color = this.getAttributeColor('left', attr)
      const column = columns.find(c => c.name === col)
      const colText = labelColumn(column && column.localizeKey)
      const onRemove = () => onChange(R.without([[attr, col]], mappings))
      return (
        <Label.Group>
          <Label content={attr} pointing="right" color={color} basic />
          <Label content={colText} onRemove={onRemove} pointing="left" color={color} basic />
        </Label.Group>
      )
    }
    const filteredMappings = mappings.filter(x => columns.some(col => col.name === x[1]))
    const grouppedColumns = groupByToArray(columns, x => x.groupNumber)
    return (
      <Grid>
        <Grid.Row>
          <Grid.Column width={5}>
            <Header content={localize('VariablesOfDataSource')} as="h5" />
            <Segment>{attributes.map(x => this.renderItem('left', x))}</Segment>
          </Grid.Column>
          <Grid.Column width={11}>
            <Header content={localize('VariablesOfDatabase')} as="h5" />
            <Segment>
              {grouppedColumns.map(group => (
                <div>
                  {group.value.map(x =>
                    this.renderItem('right', x.name, labelColumn(x.localizeKey)))}
                </div>
              ))}
            </Segment>
          </Grid.Column>
        </Grid.Row>
        <Grid.Row>
          <Grid.Column width={5} floated="left">
            <br />
            {mapping.touched && hasValue(mapping.errors) && (
              <Message title={localize(mapping.label)} list={mapping.errors.map(localize)} error />
            )}
            {attribs.touched && hasValue(attribs.errors) && (
              <Message title={localize(attribs.label)} list={attribs.errors.map(localize)} error />
            )}
          </Grid.Column>
          <Grid.Column width={11} textAlign="center" floated="right">
            <Header content={localize('VariablesMappingResults')} as="h5" />
            <Segment>
              <ListWithDnd
                value={filteredMappings}
                onChange={onChange}
                renderItem={renderValueItem}
                getItemKey={R.join('-')}
                listProps={{ className: styles['values-root'] }}
                listItemProps={{ className: styles['mappings-item'] }}
              />
            </Segment>
          </Grid.Column>
        </Grid.Row>
      </Grid>
    )
  }
}

export default MappingsEditor
